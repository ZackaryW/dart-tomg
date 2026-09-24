import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:source_gen/source_gen.dart';
import 'package:tomg/tomg.dart';

import 'cli/errors.dart';
import 'cli/project.dart';
import 'registry_document.dart';

/// Generates a `const` registry (and, where needed, a typed decode
/// companion) for each class annotated with `@TomgRegistry`.
///
/// See `openspec/changes/add-tomg-generator/specs/toml-codegen/spec.md` and
/// `.../specs/field-obfuscation/spec.md` for the behavior this implements.
class TomgGenerator extends GeneratorForAnnotation<TomgRegistry> {
  static const _obfusChecker = TypeChecker.typeNamed(Obfus);
  static final _digestPattern = RegExp(r'^sha256:[0-9a-f]{64}$');
  static final _environmentReference = RegExp(
    r'^\$([A-Za-z_][A-Za-z0-9_]*)(?:=(.*))?$',
    dotAll: true,
  );

  TomgGenerator({Map<String, String>? environment})
    : _environment = Map<String, String>.unmodifiable(
        environment ?? Platform.environment,
      );

  final Map<String, String> _environment;

  @override
  Future<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) async {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@TomgRegistry can only annotate a class.',
        element: element,
      );
    }
    final className = element.name!;

    final source = annotation.read('source').stringValue;
    final keyField = annotation.read('key').stringValue;
    final digestReader = annotation.peek('digest');
    final sourceDigest = digestReader == null || digestReader.isNull
        ? null
        : digestReader.stringValue;
    final tomlContent = await _readTomlContent(
      source: source,
      digest: sourceDigest,
      className: className,
      element: element,
      buildStep: buildStep,
    );

    final TomgRegistryDocument registryDocument;
    try {
      registryDocument = TomgRegistryDocument.parse(
        tomlContent,
        source: source,
      );
    } on TomgDocumentException catch (e) {
      throw InvalidGenerationSourceError(
        '${e.message}${e.message.startsWith('Failed to parse') ? ' for $className' : ''}',
        element: element,
      );
    }
    final document = registryDocument.rows;
    final tomlObfuscatedFields = registryDocument.obfuscatedFields;

    final ctor = element.unnamedConstructor;
    if (ctor == null || !ctor.isConst) {
      throw InvalidGenerationSourceError(
        '@TomgRegistry requires $className to have a const unnamed '
        'constructor.',
        element: element,
      );
    }

    final obfuscatedFields = <String>{
      for (final field in element.fields)
        if (field.metadata.annotations.any(_isObfusAnnotation)) field.name!,
    };

    final namedParams = <String, FormalParameterElement>{
      for (final p in ctor.formalParameters)
        if (p.isNamed) p.name!: p,
    };
    if (ctor.formalParameters.any((parameter) => !parameter.isNamed)) {
      throw InvalidGenerationSourceError(
        '@TomgRegistry requires $className\'s constructor to use named '
        'parameters (TOML keys are matched to parameters by name).',
        element: element,
      );
    }
    if (!namedParams.containsKey(keyField)) {
      throw InvalidGenerationSourceError(
        '@TomgRegistry names key "$keyField", but $className\'s constructor '
        'has no matching named parameter.',
        element: element,
      );
    }

    final modelInspector = _ModelInspector(
      source: source,
      rootElement: element,
    );

    _validateObfuscationMetadataAgreement(
      tomlObfuscatedFields,
      dartFields: obfuscatedFields,
      constructorFields: namedParams.keys.toSet(),
      source: source,
      className: className,
      element: element,
    );

    for (final param in namedParams.values) {
      modelInspector.validateType(
        param.type,
        context: '$className.${param.name}',
      );
      if (obfuscatedFields.contains(param.name) &&
          (_isEnumType(param.type) ||
              _isListType(param.type) ||
              modelInspector.isModelType(param.type))) {
        throw InvalidGenerationSourceError(
          '@Obfus is not supported on field "$className.${param.name}" in '
          '"$source" (${param.type.getDisplayString()}).',
          element: element,
        );
      }
    }

    final keyParam = namedParams[keyField]!;
    if (_isListType(keyParam.type) ||
        modelInspector.isModelType(keyParam.type)) {
      throw InvalidGenerationSourceError(
        '@TomgRegistry key "$keyField" on $className has object or '
        'collection type "${keyParam.type.getDisplayString()}"; structured '
        'registry keys are unsupported in "$source".',
        element: element,
      );
    }

    final buffer = StringBuffer();
    final entries = <String>[];
    final keyTables = <Object?, String>{};

    for (final tableEntry in document.entries) {
      final tableName = tableEntry.key;
      final table = tableEntry.value;
      final row = table;

      for (final fieldName in row.keys) {
        if (!namedParams.containsKey(fieldName)) {
          throw InvalidGenerationSourceError(
            'Table "$tableName" in "$source" contains unknown field '
            '"$fieldName" for $className.',
            element: element,
          );
        }
      }

      if (!row.containsKey(keyField)) {
        throw InvalidGenerationSourceError(
          'Table "$tableName" in "$source" is missing required key field '
          '"$keyField" (constructing $className).',
          element: element,
        );
      }

      final renderedRow = <String, _RenderedValue>{};
      for (final param in namedParams.values) {
        final name = param.name!;
        if (row.containsKey(name)) {
          renderedRow[name] = _renderValue(
            param.type,
            row[name],
            obfuscate: obfuscatedFields.contains(name),
            source: source,
            context: '$tableName.$name',
            element: element,
            modelInspector: modelInspector,
          );
        }
      }

      final keyRendered = renderedRow[keyField]!;
      final keyLiteral = keyRendered.literal;
      final keyValue = keyRendered.canonical;
      final firstTable = keyTables[keyValue];
      if (firstTable != null) {
        throw InvalidGenerationSourceError(
          'Duplicate registry key $keyLiteral in "$source": tables '
          '"$firstTable" and "$tableName" use the same "$keyField" value.',
          element: element,
        );
      }
      keyTables[keyValue] = tableName;

      final args = <String>[];
      for (final param in namedParams.values) {
        final name = param.name;
        if (!row.containsKey(name)) {
          if (param.isRequiredNamed) {
            throw InvalidGenerationSourceError(
              'Table "$tableName" in "$source" is missing required field '
              '"$name" for $className.',
              element: element,
            );
          }
          // Optional and omitted: skip the argument so the class default
          // applies.
          continue;
        }
        final literal = renderedRow[name]!.literal;
        args.add('$name: $literal');
      }

      entries.add('  $keyLiteral: $className(${args.join(', ')}),');
    }

    final keyType = _typeReference(namedParams[keyField]!.type, element);
    buffer.writeln(
      'const Map<$keyType, $className> \$$className = '
      '<$keyType, $className>{',
    );
    for (final entry in entries) {
      buffer.writeln(entry);
    }
    buffer.writeln('};');

    if (obfuscatedFields.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(
        _companionFor(element, namedParams.values, obfuscatedFields),
      );
    }

    return buffer.toString();
  }

  Future<String> _readTomlContent({
    required String source,
    required String? digest,
    required String className,
    required Element element,
    required BuildStep buildStep,
  }) async {
    if (digest == null) {
      final sourceUri = Uri.parse(source);
      if (!sourceUri.hasScheme) {
        final normalized = p.url.normalize(
          p.url.join(p.url.dirname(buildStep.inputId.path), source),
        );
        if (normalized == '..' || normalized.startsWith('../')) {
          throw InvalidGenerationSourceError(
            '@TomgRegistry on $className names external source "$source" '
            'without a digest. Run `dart run tomgen build` to regenerate the '
            'model.',
            element: element,
          );
        }
      }
      final AssetId tomlAssetId;
      try {
        tomlAssetId = AssetId.resolve(sourceUri, from: buildStep.inputId);
      } on Object {
        throw InvalidGenerationSourceError(
          '@TomgRegistry on $className names external source "$source" '
          'without a digest. Run `dart run tomgen build` to regenerate the '
          'model.',
          element: element,
        );
      }
      if (tomlAssetId.package != buildStep.inputId.package) {
        throw InvalidGenerationSourceError(
          '@TomgRegistry on $className names external source "$source" '
          'without a digest. Run `dart run tomgen build` to regenerate the '
          'model.',
          element: element,
        );
      }
      if (!await buildStep.canRead(tomlAssetId)) {
        throw InvalidGenerationSourceError(
          '@TomgRegistry on $className names "$source", but no such build '
          'input was found at ${tomlAssetId.path}.',
          element: element,
        );
      }
      return buildStep.readAsString(tomlAssetId);
    }

    if (!_digestPattern.hasMatch(digest)) {
      throw InvalidGenerationSourceError(
        '@TomgRegistry on $className has malformed digest "$digest" for '
        '"$source"; expected sha256 followed by 64 lowercase hexadecimal '
        'characters. Run `dart run tomgen build` to regenerate the model.',
        element: element,
      );
    }

    try {
      final packageRoot = locateConfiguredPackageRoot(
        buildStep.inputId.package,
      );
      final boundary = discoverSourceBoundary(packageRoot);
      final sourcePath = resolveProjectSourcePath(
        packageRoot: packageRoot,
        boundary: boundary,
        relativePath: source,
        description: 'external source "$source" for $className',
        mustExist: true,
      );
      if (isContainedBy(packageRoot, sourcePath)) {
        throw const TomgenException(
          'A digest is only valid for a source outside the package.',
        );
      }
      final sourceFile = File(sourcePath);
      if (FileSystemEntity.typeSync(sourcePath) != FileSystemEntityType.file) {
        throw TomgenException('External source is not a file: $sourcePath');
      }
      final bytes = sourceFile.readAsBytesSync();
      final actual = 'sha256:${sha256.convert(bytes)}';
      if (actual != digest) {
        throw TomgenException(
          'External source "$source" is stale: its SHA-256 digest no longer '
          'matches the generated model.',
        );
      }
      return utf8.decode(bytes);
    } on TomgenException catch (error) {
      throw InvalidGenerationSourceError(
        '@TomgRegistry on $className cannot read "$source": ${error.message} '
        'Run `dart run tomgen build` to regenerate the model.',
        element: element,
      );
    } on FileSystemException catch (error) {
      throw InvalidGenerationSourceError(
        '@TomgRegistry on $className cannot read "$source": ${error.message} '
        'Run `dart run tomgen build` to regenerate the model.',
        element: element,
      );
    }
  }

  void _validateObfuscationMetadataAgreement(
    Set<String>? tomlFields, {
    required Set<String> dartFields,
    required Set<String> constructorFields,
    required String source,
    required String className,
    required Element element,
  }) {
    if (tomlFields == null) return;

    final unknownFields = tomlFields.difference(constructorFields).toList()
      ..sort();
    if (unknownFields.isNotEmpty) {
      throw InvalidGenerationSourceError(
        'TOML metadata "__tomg.obfuscate" in "$source" names unknown '
        '${unknownFields.length == 1 ? 'field' : 'fields'} for $className: '
        '${unknownFields.join(', ')}.',
        element: element,
      );
    }

    final missingDartAnnotations = tomlFields.difference(dartFields).toList()
      ..sort();
    if (missingDartAnnotations.isNotEmpty) {
      throw InvalidGenerationSourceError(
        'TOML metadata "__tomg.obfuscate" in "$source" names '
        '${missingDartAnnotations.join(', ')}, but '
        '${missingDartAnnotations.length == 1 ? 'that field is' : 'those fields are'} '
        'not marked @Obfus on $className.',
        element: element,
      );
    }

    final missingTomlDeclarations = dartFields.difference(tomlFields).toList()
      ..sort();
    if (missingTomlDeclarations.isNotEmpty) {
      throw InvalidGenerationSourceError(
        'Dart @Obfus ${missingTomlDeclarations.length == 1 ? 'field' : 'fields'} '
        '${missingTomlDeclarations.join(', ')} on $className '
        '${missingTomlDeclarations.length == 1 ? 'is' : 'are'} missing from '
        '"__tomg.obfuscate" in "$source".',
        element: element,
      );
    }
  }

  bool _isObfusAnnotation(ElementAnnotation annotation) {
    final value = annotation.computeConstantValue();
    final type = value?.type;
    return type != null && _obfusChecker.isExactlyType(type);
  }

  String _companionFor(
    ClassElement classElement,
    Iterable<FormalParameterElement> params,
    Set<String> obfuscatedFields,
  ) {
    final className = classElement.name!;
    final companion = StringBuffer();
    companion.writeln('/// Decoded view of [$className]\'s `@Obfus` fields.');
    companion.writeln('class ${className}Deobf {');
    companion.writeln('  const ${className}Deobf(this._o);');
    companion.writeln();
    companion.writeln('  final $className _o;');
    companion.writeln();
    for (final param in params) {
      final name = param.name;
      final typeName = _typeReference(param.type, classElement);
      if (obfuscatedFields.contains(name)) {
        companion.writeln('  $typeName get $name => _o.$name.deobf;');
      } else {
        companion.writeln('  $typeName get $name => _o.$name;');
      }
    }
    companion.write('}');
    return companion.toString();
  }

  /// Renders [value] as a double-quoted Dart string literal. `jsonEncode`
  /// handles quote/backslash/control-char escaping (JSON's escape set is a
  /// subset of Dart's), but JSON has no notion of Dart's `$` interpolation
  /// marker, so it is escaped separately - otherwise a plaintext or
  /// ciphertext value containing `$` would produce invalid or
  /// misinterpreted generated Dart.
  String _dartStringLiteral(String value) =>
      jsonEncode(value).replaceAll(r'$', r'\$');

  _ResolvedValue _resolveEnvironmentValue(
    DartType dartType,
    Object? tomlValue, {
    required String source,
    required String context,
    required Element element,
  }) {
    if (tomlValue is! String || !tomlValue.startsWith(r'$')) {
      return _ResolvedValue(tomlValue);
    }
    if (tomlValue.startsWith(r'$$')) {
      return _ResolvedValue(tomlValue.substring(1));
    }

    final match = _environmentReference.firstMatch(tomlValue);
    if (match == null) {
      throw InvalidGenerationSourceError(
        'Invalid environment reference at "$context" in "$source": use '
        r'$VAR, $VAR=default, or $$ for a literal leading dollar sign.',
        element: element,
      );
    }

    final variable = match.group(1)!;
    final fallback = match.group(2);
    final resolved = _environment.containsKey(variable)
        ? _environment[variable]!
        : fallback;
    if (resolved == null) {
      throw InvalidGenerationSourceError(
        'Environment variable "$variable" required at "$context" in '
        '"$source" is not set and has no default.',
        element: element,
      );
    }

    final typeName = dartType.getDisplayString();
    final scalarName = _scalarTypeName(dartType);
    final Object? converted = switch (scalarName) {
      'String' => resolved,
      'int' => int.tryParse(resolved, radix: 10),
      'double' => double.tryParse(resolved),
      'bool' => switch (resolved) {
        'true' => true,
        'false' => false,
        _ => null,
      },
      _ when _isEnumType(dartType) => resolved,
      _ => resolved,
    };
    if (converted == null) {
      throw InvalidGenerationSourceError(
        'Environment variable "$variable" at "$context" in "$source" '
        'cannot be converted to $typeName.',
        element: element,
      );
    }
    return _ResolvedValue(converted, environmentVariable: variable);
  }

  _RenderedValue _renderValue(
    DartType dartType,
    Object? tomlValue, {
    required bool obfuscate,
    required String source,
    required String context,
    required Element element,
    required _ModelInspector modelInspector,
  }) {
    if (_isListType(dartType)) {
      if (obfuscate) {
        throw InvalidGenerationSourceError(
          '@Obfus is not supported on collection field "$context" in '
          '"$source" (${dartType.getDisplayString()}).',
          element: element,
        );
      }
      if (tomlValue is! List) {
        throw InvalidGenerationSourceError(
          'Expected a TOML array for ${dartType.getDisplayString()} at '
          '"$context" in "$source"; one string or environment reference '
          'cannot represent a whole list.',
          element: element,
        );
      }
      final listType = dartType as InterfaceType;
      final itemType = listType.typeArguments.single;
      if (_isListType(itemType)) {
        throw InvalidGenerationSourceError(
          'Unsupported nested list type "${dartType.getDisplayString()}" at '
          '"$context" in "$source".',
          element: element,
        );
      }
      final items = <_RenderedValue>[];
      for (var index = 0; index < tomlValue.length; index++) {
        items.add(
          _renderValue(
            itemType,
            tomlValue[index],
            obfuscate: false,
            source: source,
            context: '$context[$index]',
            element: element,
            modelInspector: modelInspector,
          ),
        );
      }
      final itemTypeName = _typeReference(itemType, element);
      return _RenderedValue(
        items.map((item) => item.resolved).toList(growable: false),
        canonical: items.map((item) => item.canonical).toList(growable: false),
        literal:
            'const <$itemTypeName>[${items.map((item) => item.literal).join(', ')}]',
      );
    }

    if (modelInspector.isModelType(dartType)) {
      if (obfuscate) {
        throw InvalidGenerationSourceError(
          '@Obfus is not supported on object field "$context" in "$source" '
          '(${dartType.getDisplayString()}).',
          element: element,
        );
      }
      if (tomlValue is! Map || tomlValue.keys.any((key) => key is! String)) {
        throw InvalidGenerationSourceError(
          'Expected a TOML table for ${dartType.getDisplayString()} at '
          '"$context" in "$source", got: ${_safeValueDescription(tomlValue)}.',
          element: element,
        );
      }
      final description = modelInspector.describe(dartType, context: context);
      final object = Map<String, dynamic>.from(tomlValue);
      for (final fieldName in object.keys) {
        if (!description.namedParams.containsKey(fieldName)) {
          throw InvalidGenerationSourceError(
            'Object "$context" in "$source" contains unknown field '
            '"$fieldName" for ${description.element.name}.',
            element: element,
          );
        }
      }
      final args = <String>[];
      final canonical = <Object?>[];
      for (final param in description.namedParams.values) {
        final name = param.name!;
        if (!object.containsKey(name)) {
          if (param.isRequiredNamed) {
            throw InvalidGenerationSourceError(
              'Object "$context" in "$source" is missing required field '
              '"$name" for ${description.element.name}.',
              element: element,
            );
          }
          continue;
        }
        final rendered = _renderValue(
          param.type,
          object[name],
          obfuscate: false,
          source: source,
          context: '$context.$name',
          element: element,
          modelInspector: modelInspector,
        );
        args.add('$name: ${rendered.literal}');
        canonical
          ..add(name)
          ..add(rendered.canonical);
      }
      var reference = _typeReference(dartType, element);
      if (reference.endsWith('?')) {
        reference = reference.substring(0, reference.length - 1);
      }
      return _RenderedValue(
        object,
        canonical: (description.element.id, canonical),
        literal: '$reference(${args.join(', ')})',
      );
    }

    final resolved = _resolveEnvironmentValue(
      dartType,
      tomlValue,
      source: source,
      context: context,
      element: element,
    );
    final value = resolved.value;

    if (_isEnumType(dartType)) {
      if (obfuscate) {
        throw InvalidGenerationSourceError(
          '@Obfus is not supported on enum field "$context" in "$source" '
          '(${dartType.getDisplayString()}).',
          element: element,
        );
      }
      final enumElement = (dartType as InterfaceType).element as EnumElement;
      final members = enumElement.constants
          .map((constant) => constant.name!)
          .toList(growable: false);
      if (value is! String || !members.contains(value)) {
        final supplied = resolved.environmentVariable == null
            ? 'value ${value is String ? _dartStringLiteral(value) : value}'
            : 'environment variable "${resolved.environmentVariable}"';
        throw InvalidGenerationSourceError(
          'Invalid enum $supplied at "$context" in "$source": expected '
          '${enumElement.name} member ${members.join(', ')}.',
          element: element,
        );
      }
      final reference = '${_typeReference(dartType, element)}.$value';
      return _RenderedValue(
        value,
        canonical: (enumElement.id, value),
        literal: reference,
        environmentVariable: resolved.environmentVariable,
      );
    }

    final typeName = dartType.getDisplayString();
    switch (_scalarTypeName(dartType)) {
      case 'String':
        if (value is! String) {
          throw InvalidGenerationSourceError(
            'Expected a string at "$context" in "$source", got: '
            '${_safeValueDescription(value)}',
            element: element,
          );
        }
        final encoded = obfuscate ? TomgCodec.encodeString(value) : value;
        return _RenderedValue(
          value,
          literal: _dartStringLiteral(encoded),
          environmentVariable: resolved.environmentVariable,
        );
      case 'int':
        if (value is! int) {
          throw InvalidGenerationSourceError(
            'Expected an int at "$context" in "$source", got: '
            '${_safeValueDescription(value)}',
            element: element,
          );
        }
        final encoded = obfuscate ? TomgCodec.encodeInt(value) : value;
        return _RenderedValue(
          value,
          literal: '$encoded',
          environmentVariable: resolved.environmentVariable,
        );
      case 'double':
        final numValue = value is int ? value.toDouble() : value;
        if (numValue is! double) {
          throw InvalidGenerationSourceError(
            'Expected a double at "$context" in "$source", got: '
            '${_safeValueDescription(value)}',
            element: element,
          );
        }
        final encoded = obfuscate ? TomgCodec.encodeDouble(numValue) : numValue;
        if (!obfuscate) {
          return _RenderedValue(
            numValue,
            literal: _plainDoubleLiteral(encoded),
            environmentVariable: resolved.environmentVariable,
          );
        }
        if (!encoded.isFinite) {
          throw InvalidGenerationSourceError(
            'Cannot obfuscate double at "$context": its '
            'ciphertext is not a finite Dart constant.',
            element: element,
          );
        }
        final literal = encoded.toString();
        final reparsed = double.parse(literal);
        if (_doubleBits(reparsed) != _doubleBits(encoded) ||
            _doubleBits(TomgCodec.decodeDouble(reparsed)) !=
                _doubleBits(numValue)) {
          throw InvalidGenerationSourceError(
            'Cannot obfuscate double at "$context" without '
            'losing its IEEE-754 value in generated Dart.',
            element: element,
          );
        }
        return _RenderedValue(
          numValue,
          literal: literal,
          environmentVariable: resolved.environmentVariable,
        );
      case 'bool':
        if (value is! bool) {
          throw InvalidGenerationSourceError(
            'Expected a bool at "$context" in "$source", got: '
            '${_safeValueDescription(value)}',
            element: element,
          );
        }
        if (obfuscate) {
          throw InvalidGenerationSourceError(
            '@Obfus is not supported on bool fields ("$context").',
            element: element,
          );
        }
        return _RenderedValue(
          value,
          literal: value.toString(),
          environmentVariable: resolved.environmentVariable,
        );
      default:
        throw InvalidGenerationSourceError(
          'Unsupported field type "$typeName" at "$context" - tomg supports '
          'String, int, double, and bool.',
          element: element,
        );
    }
  }

  String? _scalarTypeName(DartType type) {
    if (type is! InterfaceType || !type.element.library.isDartCore) {
      return null;
    }
    return switch (type.element.name) {
      'String' || 'int' || 'double' || 'bool' => type.element.name,
      _ => null,
    };
  }

  bool _isEnumType(DartType type) =>
      type is InterfaceType && type.element is EnumElement;

  bool _isListType(DartType type) =>
      type is InterfaceType &&
      type.element.library.isDartCore &&
      type.element.name == 'List';

  String _typeReference(DartType type, Element contextElement) {
    if (type is! InterfaceType) return type.getDisplayString();
    final element = type.element;
    final name = element.name!;
    final typeArguments = type.typeArguments.isEmpty
        ? ''
        : '<${type.typeArguments.map((argument) => _typeReference(argument, contextElement)).join(', ')}>';
    final suffix = type.nullabilitySuffix == NullabilitySuffix.question
        ? '?'
        : '';
    if (element.library == contextElement.library ||
        element.library.isDartCore) {
      return '$name$typeArguments$suffix';
    }

    final imports = contextElement.library!.firstFragment.libraryImports.where(
      (import) => import.importedLibrary == element.library,
    );
    LibraryImport? selected;
    for (final import in imports) {
      if (import.prefix == null) return '$name$typeArguments$suffix';
      selected ??= import;
    }
    final prefix = selected?.prefix?.name;
    return prefix == null
        ? '$name$typeArguments$suffix'
        : '$prefix.$name$typeArguments$suffix';
  }

  String _safeValueDescription(Object? value) => switch (value) {
    String() => 'a string value',
    List() => 'a TOML array',
    Map() => 'a TOML table',
    _ => '$value',
  };

  String _plainDoubleLiteral(double value) {
    if (value.isNaN) return 'double.nan';
    if (value == double.infinity) return 'double.infinity';
    if (value == double.negativeInfinity) return 'double.negativeInfinity';
    return value.toString();
  }

  int _doubleBits(double value) =>
      (ByteData(8)..setFloat64(0, value)).getUint64(0);
}

final class _ModelDescription {
  const _ModelDescription({required this.element, required this.namedParams});

  final ClassElement element;
  final Map<String, FormalParameterElement> namedParams;
}

final class _ModelInspector {
  _ModelInspector({required this.source, required this.rootElement})
    : _active = <ClassElement>[rootElement];

  final String source;
  final ClassElement rootElement;
  final Map<ClassElement, _ModelDescription> _cache =
      <ClassElement, _ModelDescription>{};
  final List<ClassElement> _active;

  bool isModelType(DartType type) =>
      type is InterfaceType &&
      !_isScalar(type) &&
      !_isEnum(type) &&
      !_isList(type);

  void validateType(
    DartType type, {
    required String context,
    bool insideList = false,
  }) {
    if (_isScalar(type) || _isEnum(type)) return;
    if (_isList(type)) {
      if (insideList) {
        throw InvalidGenerationSourceError(
          'Unsupported nested list type "${type.getDisplayString()}" at '
          '"$context" in "$source".',
          element: rootElement,
        );
      }
      validateType(
        (type as InterfaceType).typeArguments.single,
        context: '$context[]',
        insideList: true,
      );
      return;
    }
    describe(type, context: context);
  }

  _ModelDescription describe(DartType type, {required String context}) {
    if (type is! InterfaceType || type.element is! ClassElement) {
      _unsupported(type, context);
    }
    final classElement = type.element as ClassElement;
    final cached = _cache[classElement];
    if (cached != null) return cached;
    if (_active.contains(classElement)) {
      final cycle = <String>[
        ..._active.map((item) => item.name!),
        classElement.name!,
      ].join(' -> ');
      throw InvalidGenerationSourceError(
        'Nested model cycle $cycle reaches "$context" in "$source".',
        element: rootElement,
      );
    }
    if (classElement.isAbstract || !classElement.isConstructable) {
      throw InvalidGenerationSourceError(
        'Nested model "${classElement.name}" at "$context" in "$source" '
        'must be a concrete constructable class.',
        element: rootElement,
      );
    }
    if (classElement.typeParameters.isNotEmpty ||
        type.typeArguments.isNotEmpty) {
      throw InvalidGenerationSourceError(
        'Nested model "${type.getDisplayString()}" at "$context" in '
        '"$source" must be non-generic.',
        element: rootElement,
      );
    }
    final ctor = classElement.unnamedConstructor;
    if (ctor == null || !ctor.isConst || ctor.isFactory) {
      throw InvalidGenerationSourceError(
        'Nested model "${classElement.name}" at "$context" in "$source" '
        'must have a non-factory const unnamed constructor.',
        element: rootElement,
      );
    }
    if (ctor.formalParameters.any((parameter) => !parameter.isNamed)) {
      throw InvalidGenerationSourceError(
        'Nested model "${classElement.name}" at "$context" in "$source" '
        'must use only named constructor parameters.',
        element: rootElement,
      );
    }
    final params = <String, FormalParameterElement>{
      for (final param in ctor.formalParameters) param.name!: param,
    };
    final obfuscated = <String>{
      for (final field in classElement.fields)
        if (field.metadata.annotations.any(_isObfus)) field.name!,
      for (final param in ctor.formalParameters)
        if (param.metadata.annotations.any(_isObfus)) param.name!,
    };
    if (obfuscated.isNotEmpty) {
      final fields = obfuscated.toList()..sort();
      throw InvalidGenerationSourceError(
        '@Obfus is not supported inside nested model '
        '"${classElement.name}" at "$context" in "$source" '
        '(fields: ${fields.join(', ')}).',
        element: rootElement,
      );
    }

    _active.add(classElement);
    try {
      for (final param in params.values) {
        validateType(param.type, context: '$context.${param.name}');
      }
    } finally {
      _active.removeLast();
    }
    final description = _ModelDescription(
      element: classElement,
      namedParams: Map<String, FormalParameterElement>.unmodifiable(params),
    );
    _cache[classElement] = description;
    return description;
  }

  Never _unsupported(DartType type, String context) {
    throw InvalidGenerationSourceError(
      'Unsupported field type "${type.getDisplayString()}" at "$context" '
      'in "$source"; tomg supports scalar values, enums, nested const '
      'models, and one-dimensional List values of those types.',
      element: rootElement,
    );
  }

  bool _isScalar(DartType type) =>
      type is InterfaceType &&
      type.element.library.isDartCore &&
      const <String>{
        'String',
        'int',
        'double',
        'bool',
      }.contains(type.element.name);

  bool _isEnum(DartType type) =>
      type is InterfaceType && type.element is EnumElement;

  bool _isList(DartType type) =>
      type is InterfaceType &&
      type.element.library.isDartCore &&
      type.element.name == 'List';

  bool _isObfus(ElementAnnotation annotation) {
    final type = annotation.computeConstantValue()?.type;
    return type != null && TomgGenerator._obfusChecker.isExactlyType(type);
  }
}

final class _ResolvedValue {
  const _ResolvedValue(this.value, {this.environmentVariable});

  final Object? value;
  final String? environmentVariable;
}

final class _RenderedValue {
  const _RenderedValue(
    this.resolved, {
    Object? canonical,
    required this.literal,
    this.environmentVariable,
  }) : canonical = canonical ?? resolved;

  final Object? resolved;
  final Object? canonical;
  final String literal;
  final String? environmentVariable;
}

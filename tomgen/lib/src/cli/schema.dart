import '../registry_document.dart';
import 'config.dart';
import 'errors.dart';

enum TomgenScalarKind { string, integer, doubleValue, boolean }

final RegExp _environmentReference = RegExp(
  r'^\$[A-Za-z_][A-Za-z0-9_]*(?:=.*)?$',
  dotAll: true,
);

/// A dotted field path with optional list indices for precise diagnostics.
final class TomgenPath {
  const TomgenPath([this.segments = const <Object>[]]);

  final List<Object> segments;

  TomgenPath field(String name) =>
      TomgenPath(List<Object>.unmodifiable(<Object>[...segments, name]));

  TomgenPath index(int value) =>
      TomgenPath(List<Object>.unmodifiable(<Object>[...segments, value]));

  List<String> get fields =>
      segments.whereType<String>().toList(growable: false);

  String get dotted => fields.join('.');

  @override
  String toString() {
    final buffer = StringBuffer();
    for (final segment in segments) {
      if (segment is int) {
        buffer.write('[$segment]');
      } else {
        if (buffer.isNotEmpty) buffer.write('.');
        buffer.write(segment);
      }
    }
    return buffer.toString();
  }
}

/// A scalar, enum, nested-model, or one-dimensional list field type.
final class TomgenType {
  const TomgenType.scalar(TomgenScalarKind value)
    : scalar = value,
      enumConfig = null,
      modelName = null,
      itemType = null;

  const TomgenType.enumeration(TomgenEnumConfig value)
    : scalar = null,
      enumConfig = value,
      modelName = null,
      itemType = null;

  const TomgenType.model(String value)
    : scalar = null,
      enumConfig = null,
      modelName = value,
      itemType = null;

  const TomgenType.list(TomgenType value)
    : scalar = null,
      enumConfig = null,
      modelName = null,
      itemType = value;

  final TomgenScalarKind? scalar;
  final TomgenEnumConfig? enumConfig;
  final String? modelName;
  final TomgenType? itemType;

  bool get isList => itemType != null;
  bool get isModel => modelName != null;

  String get dartType {
    final item = itemType;
    if (item != null) return 'List<${item.dartType}>';
    return enumConfig?.name ?? modelName ?? _scalarDartType(scalar!);
  }

  bool get canObfuscate =>
      itemType == null &&
      enumConfig == null &&
      modelName == null &&
      scalar != TomgenScalarKind.boolean;
}

final class TomgenField {
  const TomgenField({
    required this.name,
    required this.type,
    required this.required,
    required this.defaultValue,
    required this.obfuscated,
  });

  final String name;
  final TomgenType type;
  final bool required;
  final Object? defaultValue;
  final bool obfuscated;

  bool get hasDefault => defaultValue != null;
  bool get nullable => !required && !hasDefault;
  String get dartType => '${type.dartType}${nullable ? '?' : ''}';
}

final class TomgenModel {
  const TomgenModel({
    required this.name,
    required this.path,
    required this.fields,
    required this.isRoot,
  });

  final String name;
  final TomgenPath path;
  final List<TomgenField> fields;
  final bool isRoot;
}

final class TomgenSchema {
  TomgenSchema({
    required this.target,
    required this.models,
    required this.enumDeclarations,
  });

  final TomgenTarget target;
  final List<TomgenModel> models;
  final List<TomgenEnumConfig> enumDeclarations;

  TomgenModel get rootModel => models.singleWhere((model) => model.isRoot);
  List<TomgenField> get fields => rootModel.fields;

  TomgenField get keyField =>
      fields.singleWhere((field) => field.name == target.key);

  static TomgenSchema infer(
    TomgenTarget target,
    TomgRegistryDocument document,
  ) {
    if (document.rows.isEmpty) {
      throw TomgenException('Target "${target.name}" has no registry rows.');
    }
    return _SchemaInference(target, document).infer();
  }
}

final class _SchemaInference {
  _SchemaInference(this.target, this.document);

  final TomgenTarget target;
  final TomgRegistryDocument document;
  final List<TomgenModel> _models = <TomgenModel>[];
  final Map<String, String> _modelPathsByName = <String, String>{};
  final Set<String> _usedDefaults = <String>{};
  final Set<String> _usedEnums = <String>{};

  TomgenSchema infer() {
    final enumNames = <String, List<String>>{};
    for (final entry in target.enums.entries) {
      final prior = enumNames[entry.value.name];
      if (prior != null && !_sameStrings(prior, entry.value.values)) {
        throw TomgenException(
          'Target "${target.name}" reuses enum name "${entry.value.name}" '
          'with conflicting member lists.',
        );
      }
      enumNames[entry.value.name] = entry.value.values;
    }

    _reserveModelName(target.model, '<root>');
    final rootOccurrences = <_ObjectOccurrence>[
      for (final row in document.rows.entries)
        _ObjectOccurrence(row.value, table: row.key, path: const TomgenPath()),
    ];
    final root = _inferModel(
      name: target.model,
      path: const TomgenPath(),
      occurrences: rootOccurrences,
      isRoot: true,
    );

    for (final path in target.defaults.keys) {
      if (!_usedDefaults.contains(path)) {
        throw TomgenException(
          'Target "${target.name}" default field "$path" does not match a '
          'leaf field in the inferred model graph.',
        );
      }
    }
    for (final path in target.enums.keys) {
      if (!_usedEnums.contains(path)) {
        throw TomgenException(
          'Target "${target.name}" enum field "$path" does not match a '
          'string leaf field in the inferred model graph.',
        );
      }
    }

    final knownRootFields = root.fields.map((field) => field.name).toSet();
    for (final name in document.obfuscatedFields ?? const <String>{}) {
      if (!knownRootFields.contains(name)) {
        throw TomgenException(
          'Target "${target.name}" obfuscation metadata names unknown field '
          '"$name".',
        );
      }
    }

    final nested = _models.where((model) => !model.isRoot).toList()
      ..sort((left, right) {
        final depth = right.path.fields.length.compareTo(
          left.path.fields.length,
        );
        return depth != 0 ? depth : left.name.compareTo(right.name);
      });
    final declarations = <TomgenEnumConfig>[
      for (final entry in enumNames.entries)
        TomgenEnumConfig(entry.key, entry.value),
    ]..sort((a, b) => a.name.compareTo(b.name));
    return TomgenSchema(
      target: target,
      models: List<TomgenModel>.unmodifiable(<TomgenModel>[...nested, root]),
      enumDeclarations: List<TomgenEnumConfig>.unmodifiable(declarations),
    );
  }

  TomgenModel _inferModel({
    required String name,
    required TomgenPath path,
    required List<_ObjectOccurrence> occurrences,
    required bool isRoot,
  }) {
    final names = <String>{};
    final values = <String, List<_LocatedValue>>{};
    final presence = <String, int>{};
    for (final occurrence in occurrences) {
      for (final entry in occurrence.value.entries) {
        if (!isDartIdentifier(entry.key)) {
          throw TomgenException(
            'Target "${target.name}", table "${occurrence.table}" has '
            'invalid Dart field identifier "${entry.key}" at '
            '"${occurrence.path.field(entry.key)}".',
          );
        }
        names.add(entry.key);
        presence[entry.key] = (presence[entry.key] ?? 0) + 1;
        (values[entry.key] ??= <_LocatedValue>[]).add(
          _LocatedValue(
            entry.value,
            table: occurrence.table,
            path: occurrence.path.field(entry.key),
          ),
        );
      }
    }

    final fieldPrefix = path.fields;
    for (final hint in <String>{
      ...target.defaults.keys,
      ...target.enums.keys,
    }) {
      final segments = hint.split('.');
      if (_isDirectChild(segments, fieldPrefix)) names.add(segments.last);
    }

    if (isRoot) {
      if (!names.contains(target.key)) {
        throw TomgenException(
          'Target "${target.name}" key "${target.key}" is not a model field.',
        );
      }
      if ((presence[target.key] ?? 0) != occurrences.length) {
        final missing = occurrences.firstWhere(
          (item) => !item.value.containsKey(target.key),
        );
        throw TomgenException(
          'Target "${target.name}", table "${missing.table}" is missing key '
          'field "${target.key}".',
        );
      }
    }

    final orderedNames = names.toList()..sort();
    if (isRoot) {
      orderedNames.remove(target.key);
      orderedNames.insert(0, target.key);
    }
    final fields = <TomgenField>[];
    for (final fieldName in orderedNames) {
      final fieldPath = path.field(fieldName);
      final dotted = fieldPath.dotted;
      final fieldValues = <_LocatedValue>[...?values[fieldName]];
      final hasDefault = target.defaults.containsKey(dotted);
      final defaultValue = target.defaults[dotted];
      if (hasDefault) {
        _usedDefaults.add(dotted);
        fieldValues.add(
          _LocatedValue(
            defaultValue,
            table: 'g.toml defaults',
            path: fieldPath,
          ),
        );
      }
      if (fieldValues.isEmpty) {
        throw TomgenException(
          'Target "${target.name}" declares field "$dotted" without any '
          'value or default evidence.',
        );
      }

      final enumConfig = target.enums[dotted];
      final shape = _inferShape(fieldValues, fieldPath, enumConfig: enumConfig);
      late TomgenType type;
      switch (shape.kind) {
        case _ShapeKind.scalar:
          type = TomgenType.scalar(shape.scalar!);
        case _ShapeKind.scalarList:
          type = TomgenType.list(TomgenType.scalar(shape.scalar!));
        case _ShapeKind.object:
          if (enumConfig != null) {
            _enumShapeError(dotted, typeDescription: 'object');
          }
          final modelName = _modelName(fieldPath, listItem: false);
          _reserveModelName(modelName, dotted);
          final childOccurrences = <_ObjectOccurrence>[
            for (final value in fieldValues)
              if (value.value is Map)
                _ObjectOccurrence(
                  Map<String, dynamic>.from(value.value as Map),
                  table: value.table,
                  path: value.path,
                ),
          ];
          _inferModel(
            name: modelName,
            path: fieldPath,
            occurrences: childOccurrences,
            isRoot: false,
          );
          type = TomgenType.model(modelName);
        case _ShapeKind.modelList:
          if (enumConfig != null) {
            _enumShapeError(dotted, typeDescription: 'model list');
          }
          final modelName = _modelName(fieldPath, listItem: true);
          _reserveModelName(modelName, '$dotted[]');
          final childOccurrences = <_ObjectOccurrence>[];
          for (final value in fieldValues) {
            if (value.value is! List) continue;
            final list = value.value as List;
            for (var index = 0; index < list.length; index++) {
              final item = list[index];
              if (item is Map) {
                childOccurrences.add(
                  _ObjectOccurrence(
                    Map<String, dynamic>.from(item),
                    table: value.table,
                    path: value.path.index(index),
                  ),
                );
              }
            }
          }
          _inferModel(
            name: modelName,
            path: fieldPath,
            occurrences: childOccurrences,
            isRoot: false,
          );
          type = TomgenType.list(TomgenType.model(modelName));
      }

      if (enumConfig != null) {
        if (shape.kind != _ShapeKind.scalar &&
            shape.kind != _ShapeKind.scalarList) {
          _enumShapeError(dotted, typeDescription: type.dartType);
        }
        if (shape.scalar != TomgenScalarKind.string) {
          _enumShapeError(
            dotted,
            typeDescription: shape.kind == _ShapeKind.scalarList
                ? '${_scalarDartType(shape.scalar!)} list'
                : _scalarDartType(shape.scalar!),
          );
        }
        _usedEnums.add(dotted);
        _validateEnumValues(dotted, enumConfig, fieldValues);
        final enumType = TomgenType.enumeration(enumConfig);
        type = shape.kind == _ShapeKind.scalarList
            ? TomgenType.list(enumType)
            : enumType;
      }

      if (isRoot && fieldName == target.key && (type.isList || type.isModel)) {
        throw TomgenException(
          'Target "${target.name}" key "$fieldName" cannot be an object or '
          'list.',
        );
      }
      final obfuscated =
          isRoot && (document.obfuscatedFields?.contains(fieldName) ?? false);
      if (obfuscated && !type.canObfuscate) {
        throw TomgenException(
          'Target "${target.name}" obfuscation field "$fieldName" has '
          'unsupported type ${type.dartType}.',
        );
      }
      fields.add(
        TomgenField(
          name: fieldName,
          type: type,
          required:
              (presence[fieldName] ?? 0) == occurrences.length && !hasDefault,
          defaultValue: defaultValue,
          obfuscated: obfuscated,
        ),
      );
    }

    final model = TomgenModel(
      name: name,
      path: path,
      fields: List<TomgenField>.unmodifiable(fields),
      isRoot: isRoot,
    );
    _models.add(model);
    return model;
  }

  _InferredShape _inferShape(
    List<_LocatedValue> values,
    TomgenPath path, {
    required TomgenEnumConfig? enumConfig,
  }) {
    _ShapeKind? kind;
    TomgenScalarKind? scalar;
    var sawEmptyList = false;
    for (final located in values) {
      final observed = _observe(located, target: target.name);
      if (observed.kind == null) {
        sawEmptyList = true;
        continue;
      }
      if (kind == null) {
        kind = observed.kind;
      } else if (kind != observed.kind) {
        throw TomgenException(
          'Target "${target.name}" field "$path" mixes ${_shapeName(kind)} '
          'and ${_shapeName(observed.kind!)} shapes (table '
          '"${located.table}").',
        );
      }
      if (observed.scalar != null) {
        scalar = scalar == null
            ? observed.scalar
            : _mergeScalar(
                scalar,
                observed.scalar!,
                target: target.name,
                path: path,
                context: 'table "${located.table}"',
              );
      }
    }
    if (kind == null) {
      if (sawEmptyList && enumConfig != null) {
        return const _InferredShape(
          _ShapeKind.scalarList,
          TomgenScalarKind.string,
        );
      }
      throw TomgenException(
        'Target "${target.name}" field "$path" has only empty lists, so its '
        'element type cannot be inferred.',
      );
    }
    if (sawEmptyList &&
        kind != _ShapeKind.scalarList &&
        kind != _ShapeKind.modelList) {
      throw TomgenException(
        'Target "${target.name}" field "$path" mixes ${_shapeName(kind)} and '
        'list shapes.',
      );
    }
    return _InferredShape(kind, scalar);
  }

  void _validateEnumValues(
    String path,
    TomgenEnumConfig config,
    List<_LocatedValue> values,
  ) {
    for (final located in values) {
      final items = located.value is List
          ? located.value as List
          : <Object?>[located.value];
      for (final item in items) {
        if (item is! String || _environmentReference.hasMatch(item)) continue;
        if (!config.values.contains(item)) {
          throw TomgenException(
            'Target "${target.name}" enum field "$path" has invalid value '
            '"$item" in table "${located.table}"; allowed: '
            '${config.values.join(', ')}.',
          );
        }
      }
    }
  }

  Never _enumShapeError(String path, {required String typeDescription}) {
    throw TomgenException(
      'Target "${target.name}" enum field "$path" must contain a string or '
      'string list, not $typeDescription.',
    );
  }

  String _modelName(TomgenPath path, {required bool listItem}) {
    final suffix = path.fields.map(_pascalIdentifier).join();
    return '${target.model}$suffix${listItem ? 'Item' : ''}';
  }

  void _reserveModelName(String name, String path) {
    final prior = _modelPathsByName[name];
    if (prior != null && prior != path) {
      throw TomgenException(
        'Target "${target.name}" derives model name "$name" for both '
        '"$prior" and "$path".',
      );
    }
    _modelPathsByName[name] = path;
  }
}

enum _ShapeKind { scalar, object, scalarList, modelList }

final class _InferredShape {
  const _InferredShape(this.kind, this.scalar);

  final _ShapeKind kind;
  final TomgenScalarKind? scalar;
}

final class _ObservedShape {
  const _ObservedShape(this.kind, this.scalar);

  /// `null` means an empty list without item evidence.
  final _ShapeKind? kind;
  final TomgenScalarKind? scalar;
}

final class _LocatedValue {
  const _LocatedValue(this.value, {required this.table, required this.path});

  final Object? value;
  final String table;
  final TomgenPath path;
}

final class _ObjectOccurrence {
  const _ObjectOccurrence(
    this.value, {
    required this.table,
    required this.path,
  });

  final Map<String, dynamic> value;
  final String table;
  final TomgenPath path;
}

_ObservedShape _observe(_LocatedValue located, {required String target}) {
  final value = located.value;
  final scalar = _scalarKind(value);
  if (scalar != null) return _ObservedShape(_ShapeKind.scalar, scalar);
  if (value is Map) {
    if (value.keys.any((key) => key is! String)) {
      throw TomgenException(
        'Target "$target", table "${located.table}", field '
        '"${located.path}" has an object with a non-string key.',
      );
    }
    return const _ObservedShape(_ShapeKind.object, null);
  }
  if (value is List) {
    if (value.isEmpty) return const _ObservedShape(null, null);
    final firstIsMap = value.first is Map;
    TomgenScalarKind? combined;
    for (var index = 0; index < value.length; index++) {
      final item = value[index];
      final itemPath = located.path.index(index);
      if (firstIsMap) {
        if (item is! Map) {
          throw TomgenException(
            'Target "$target", table "${located.table}", field "$itemPath" '
            'mixes object and scalar list items.',
          );
        }
        if (item.keys.any((key) => key is! String)) {
          throw TomgenException(
            'Target "$target", table "${located.table}", field "$itemPath" '
            'has an object with a non-string key.',
          );
        }
        continue;
      }
      if (item is List || item is Map) {
        throw TomgenException(
          'Target "$target", table "${located.table}", field "$itemPath" '
          'uses an unsupported nested or heterogeneous list.',
        );
      }
      final itemScalar = _scalarKind(item);
      if (itemScalar == null) {
        throw TomgenException(
          'Target "$target", table "${located.table}", field "$itemPath" '
          'has unsupported TOML value type ${item.runtimeType}.',
        );
      }
      combined = combined == null
          ? itemScalar
          : _mergeScalar(
              combined,
              itemScalar,
              target: target,
              path: located.path,
              context: 'table "${located.table}"',
            );
    }
    return firstIsMap
        ? const _ObservedShape(_ShapeKind.modelList, null)
        : _ObservedShape(_ShapeKind.scalarList, combined);
  }
  throw TomgenException(
    'Target "$target", table "${located.table}", field "${located.path}" '
    'has unsupported TOML value type ${value.runtimeType}.',
  );
}

TomgenScalarKind? _scalarKind(Object? value) {
  if (value is String) return TomgenScalarKind.string;
  if (value is bool) return TomgenScalarKind.boolean;
  if (value is int) return TomgenScalarKind.integer;
  if (value is double) return TomgenScalarKind.doubleValue;
  return null;
}

TomgenScalarKind _mergeScalar(
  TomgenScalarKind left,
  TomgenScalarKind right, {
  required String target,
  required TomgenPath path,
  required String context,
}) {
  if (left == right) return left;
  const numeric = <TomgenScalarKind>{
    TomgenScalarKind.integer,
    TomgenScalarKind.doubleValue,
  };
  if (numeric.contains(left) && numeric.contains(right)) {
    return TomgenScalarKind.doubleValue;
  }
  throw TomgenException(
    'Target "$target" field "$path" has conflicting ${left.name} and '
    '${right.name} values in $context.',
  );
}

String _scalarDartType(TomgenScalarKind scalar) => switch (scalar) {
  TomgenScalarKind.string => 'String',
  TomgenScalarKind.integer => 'int',
  TomgenScalarKind.doubleValue => 'double',
  TomgenScalarKind.boolean => 'bool',
};

String _shapeName(_ShapeKind kind) => switch (kind) {
  _ShapeKind.scalar => 'scalar',
  _ShapeKind.object => 'object',
  _ShapeKind.scalarList => 'scalar-list',
  _ShapeKind.modelList => 'model-list',
};

bool _isDirectChild(List<String> candidate, List<String> parent) {
  if (candidate.length != parent.length + 1) return false;
  for (var index = 0; index < parent.length; index++) {
    if (candidate[index] != parent[index]) return false;
  }
  return true;
}

String _pascalIdentifier(String value) {
  final parts = value.split('_').where((part) => part.isNotEmpty);
  return parts
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join();
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toml/toml.dart';

import 'errors.dart';
import 'project.dart';

final RegExp _targetPattern = RegExp(r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$');
final RegExp _identifierPattern = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

const Set<String> _dartKeywords = <String>{
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'Function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'of',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};

bool isDartIdentifier(String value) =>
    _identifierPattern.hasMatch(value) && !_dartKeywords.contains(value);

bool isTomgenTargetName(String value) => _targetPattern.hasMatch(value);

/// A validated version-1 `g.toml` manifest.
final class TomgenConfig {
  TomgenConfig({
    required this.project,
    required this.manifestFile,
    required this.outputDirectory,
    required this.outputRelative,
    required this.targets,
  });

  final TomgenProject project;
  final File manifestFile;
  final Directory outputDirectory;
  final String outputRelative;
  final List<TomgenTarget> targets;

  static TomgenConfig load(TomgenProject project) {
    final manifest = File(p.join(project.root.path, 'g.toml'));
    if (!manifest.existsSync()) {
      throw TomgenException('Missing generation manifest: ${manifest.path}');
    }

    final Map<String, dynamic> root;
    try {
      root = TomlDocument.parse(manifest.readAsStringSync()).toMap();
    } on Object catch (error) {
      throw TomgenException('Failed to parse ${manifest.path}: $error');
    }
    _rejectUnknown(root, const <String>{
      'version',
      'output',
      'targets',
    }, 'g.toml');
    if (root['version'] != 1) {
      throw TomgenException(
        '${manifest.path} has unsupported version ${root['version']}; expected 1.',
      );
    }
    final output = _requiredString(root, 'output', 'g.toml');
    final lib = Directory(p.join(project.root.path, 'lib'));
    if (!lib.existsSync()) lib.createSync();
    final outputPath = resolveContainedPath(
      root: lib,
      relativePath: p.relative(
        p.normalize(p.join(project.root.path, output)),
        from: lib.path,
      ),
      description: 'g.toml output "$output"',
      requireDescendant: true,
    );
    final normalizedOutput = p.relative(outputPath, from: project.root.path);

    final rawTargets = root['targets'];
    if (rawTargets is! Map || rawTargets.isEmpty) {
      throw TomgenException(
        '${manifest.path} must declare at least one target.',
      );
    }
    final targets = <TomgenTarget>[];
    for (final entry in rawTargets.entries) {
      final name = entry.key;
      if (name is! String || !isTomgenTargetName(name)) {
        throw TomgenException(
          'Invalid target name "$name" in ${manifest.path}.',
        );
      }
      if (entry.value is! Map) {
        throw TomgenException('Target "$name" must be a TOML table.');
      }
      targets.add(
        TomgenTarget.parse(
          name: name,
          raw: Map<String, dynamic>.from(entry.value as Map),
          project: project,
          outputDirectory: Directory(outputPath),
        ),
      );
    }
    targets.sort((a, b) => a.name.compareTo(b.name));
    return TomgenConfig(
      project: project,
      manifestFile: manifest,
      outputDirectory: Directory(outputPath),
      outputRelative: normalizedOutput,
      targets: List<TomgenTarget>.unmodifiable(targets),
    );
  }
}

final class TomgenTarget {
  const TomgenTarget({
    required this.name,
    required this.sourceRelative,
    required this.sourceFile,
    required this.outputFile,
    required this.model,
    required this.key,
    required this.defaults,
    required this.enums,
  });

  final String name;
  final String sourceRelative;
  final File sourceFile;
  final File outputFile;
  final String model;
  final String key;
  final Map<String, Object?> defaults;
  final Map<String, TomgenEnumConfig> enums;

  static TomgenTarget parse({
    required String name,
    required Map<String, dynamic> raw,
    required TomgenProject project,
    required Directory outputDirectory,
  }) {
    _rejectUnknown(raw, const <String>{
      'source',
      'model',
      'key',
      'defaults',
      'enums',
    }, 'target "$name"');
    final source = _requiredString(raw, 'source', 'target "$name"');
    final model = _requiredString(raw, 'model', 'target "$name"');
    final key = _requiredString(raw, 'key', 'target "$name"');
    _requireIdentifier(model, 'model for target "$name"');
    _requireIdentifier(key, 'key for target "$name"');

    final sourcePath = resolveContainedPath(
      root: project.root,
      relativePath: source,
      description: 'source for target "$name"',
      mustExist: true,
    );
    if (FileSystemEntity.typeSync(sourcePath) != FileSystemEntityType.file) {
      throw TomgenException('Source for target "$name" is not a file: $source');
    }

    final defaults = _stringMap(raw['defaults'], 'defaults for target "$name"');
    for (final entry in defaults.entries) {
      _requireFieldPath(entry.key, 'default field in target "$name"');
      _validateConstant(entry.value, 'default "$name.${entry.key}"');
    }

    final enums = <String, TomgenEnumConfig>{};
    final rawEnums = _stringMap(raw['enums'], 'enums for target "$name"');
    for (final entry in rawEnums.entries) {
      _requireFieldPath(entry.key, 'enum field in target "$name"');
      if (entry.value is! Map) {
        throw TomgenException('Enum "$name.${entry.key}" must be a table.');
      }
      final enumMap = Map<String, dynamic>.from(entry.value as Map);
      _rejectUnknown(enumMap, const <String>{
        'name',
        'values',
      }, 'enum "$name.${entry.key}"');
      final enumName = _requiredString(
        enumMap,
        'name',
        'enum "$name.${entry.key}"',
      );
      _requireIdentifier(enumName, 'enum name for "$name.${entry.key}"');
      final values = enumMap['values'];
      if (values is! List ||
          values.isEmpty ||
          values.any((value) => value is! String)) {
        throw TomgenException(
          'Enum "$name.${entry.key}" values must be a non-empty string array.',
        );
      }
      final members = values.cast<String>();
      final unique = <String>{};
      for (final member in members) {
        _requireIdentifier(member, 'member of enum "$enumName"');
        if (!unique.add(member)) {
          throw TomgenException('Enum "$enumName" repeats member "$member".');
        }
      }
      enums[entry.key] = TomgenEnumConfig(enumName, List.unmodifiable(members));
    }

    return TomgenTarget(
      name: name,
      sourceRelative: p.relative(sourcePath, from: project.root.path),
      sourceFile: File(sourcePath),
      outputFile: File(p.join(outputDirectory.path, '$name.dart')),
      model: model,
      key: key,
      defaults: Map.unmodifiable(defaults),
      enums: Map.unmodifiable(enums),
    );
  }
}

final class TomgenEnumConfig {
  const TomgenEnumConfig(this.name, this.values);

  final String name;
  final List<String> values;
}

void _rejectUnknown(
  Map<String, dynamic> map,
  Set<String> allowed,
  String context,
) {
  for (final key in map.keys) {
    if (!allowed.contains(key)) {
      throw TomgenException('Unknown key "$key" in $context.');
    }
  }
}

String _requiredString(Map<String, dynamic> map, String key, String context) {
  final value = map[key];
  if (value is! String || value.isEmpty) {
    throw TomgenException('$context must declare non-empty "$key".');
  }
  return value;
}

Map<String, Object?> _stringMap(Object? value, String context) {
  if (value == null) return <String, Object?>{};
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw TomgenException('$context must be a TOML table.');
  }
  return Map<String, Object?>.from(value);
}

void _requireIdentifier(String value, String context) {
  if (!isDartIdentifier(value)) {
    throw TomgenException('Invalid Dart identifier "$value" for $context.');
  }
}

void _requireFieldPath(String value, String context) {
  final segments = value.split('.');
  if (segments.isEmpty ||
      segments.any((segment) => !isDartIdentifier(segment))) {
    throw TomgenException(
      'Invalid dotted Dart field path "$value" for $context.',
    );
  }
}

void _validateConstant(Object? value, String context) {
  if (value is String || value is num || value is bool) return;
  if (value is List &&
      value.every((item) => item is String || item is num || item is bool)) {
    return;
  }
  throw TomgenException(
    '$context is not a supported scalar or flat-list constant.',
  );
}

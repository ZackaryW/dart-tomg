import 'dart:convert';
import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:toml/toml.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../registry_document.dart';
import 'config.dart';
import 'errors.dart';
import 'project.dart';
import 'schema.dart';

final class TomgenInitRequest {
  const TomgenInitRequest({
    required this.source,
    required this.target,
    required this.model,
    required this.key,
    required this.output,
    required this.createStarterSource,
  });

  const TomgenInitRequest.starter()
    : source = 'config/items.toml',
      target = 'items',
      model = 'Item',
      key = 'id',
      output = 'lib/generated',
      createStarterSource = true;

  final String source;
  final String target;
  final String model;
  final String key;
  final String output;
  final bool createStarterSource;
}

final class InitializationResult {
  const InitializationResult({
    required this.project,
    required this.created,
    required this.reused,
  });

  final TomgenProject project;
  final List<String> created;
  final List<String> reused;
}

typedef InitializationHook = void Function(String stage);

final class TomgenInitializer {
  TomgenInitializer({this.hook});

  final InitializationHook? hook;

  InitializationResult initialize(
    Directory workingDirectory,
    TomgenInitRequest request,
  ) {
    final initializationPlan = plan(workingDirectory, request);
    return initializationPlan.commit(hook: hook);
  }

  InitializationPlan plan(
    Directory workingDirectory,
    TomgenInitRequest request,
  ) {
    final project = TomgenProject.discover(workingDirectory);
    _validateDependencies(project);
    _validateNames(request);

    final sourceRelative = _normalizeRelative(request.source);
    if (p.extension(sourceRelative).toLowerCase() != '.toml') {
      throw TomgenException('--source must name a .toml file.');
    }
    final sourcePath = resolveContainedPath(
      root: project.root,
      relativePath: sourceRelative,
      description: '--source "${request.source}"',
      mustExist: !request.createStarterSource,
      requireDescendant: true,
    );
    final sourceFile = File(sourcePath);
    if (!request.createStarterSource &&
        FileSystemEntity.typeSync(sourcePath) != FileSystemEntityType.file) {
      throw TomgenException('--source must name an existing regular file.');
    }

    final outputRelative = _normalizeRelative(request.output);
    final outputPath = resolveContainedPath(
      root: project.root,
      relativePath: outputRelative,
      description: '--output "${request.output}"',
      requireDescendant: true,
    );
    final libPath = p.join(project.root.path, 'lib');
    if (!p.isWithin(libPath, outputPath)) {
      throw TomgenException('--output must be a directory beneath lib/.');
    }

    const starterContent = '[example]\nid = "example"\n';
    final sourceContent = request.createStarterSource
        ? starterContent
        : _readSource(sourceFile, sourceRelative);
    final document = _parseDocument(sourceContent, sourceRelative);
    final target = TomgenTarget(
      name: request.target,
      sourceRelative: sourceRelative,
      sourceFile: sourceFile,
      isExternal: false,
      outputFile: File(p.join(outputPath, '${request.target}.dart')),
      model: request.model,
      key: request.key,
      defaults: const <String, Object?>{},
      enums: const <String, TomgenEnumConfig>{},
    );
    TomgenSchema.infer(target, document);

    final manifest = _manifest(
      output: outputRelative,
      source: sourceRelative,
      target: request.target,
      model: request.model,
      key: request.key,
    );
    try {
      TomlDocument.parse(manifest);
    } on Object catch (error) {
      throw TomgenException('Failed to construct g.toml: $error');
    }

    final changes = <_PlannedFile>[];
    final reused = <String>[];
    final conflicts = <String>[];
    _planExact(
      project: project,
      relative: 'g.toml',
      content: manifest,
      changes: changes,
      reused: reused,
      conflicts: conflicts,
    );
    if (request.createStarterSource) {
      _planExact(
        project: project,
        relative: sourceRelative,
        content: starterContent,
        changes: changes,
        reused: reused,
        conflicts: conflicts,
      );
    } else {
      reused.add(sourceRelative);
    }

    final buildPlan = _planBuildYaml(project, sourceRelative, sourcePath);
    if (buildPlan != null) {
      if (buildPlan.conflict != null) {
        conflicts.add(buildPlan.conflict!);
      } else if (buildPlan.change != null) {
        changes.add(buildPlan.change!);
      } else {
        reused.add('build.yaml');
      }
    }

    if (conflicts.isNotEmpty) {
      throw TomgenException(
        'Initialization conflicts:\n${conflicts.map((item) => '- $item').join('\n')}',
      );
    }
    return InitializationPlan._(
      project: project,
      changes: List<_PlannedFile>.unmodifiable(changes),
      reused: List<String>.unmodifiable(reused..sort()),
    );
  }

  void _validateNames(TomgenInitRequest request) {
    if (!isTomgenTargetName(request.target)) {
      throw TomgenException('Invalid target name "${request.target}".');
    }
    if (!isDartIdentifier(request.model)) {
      throw TomgenException(
        'Invalid Dart model identifier "${request.model}".',
      );
    }
    if (!isDartIdentifier(request.key)) {
      throw TomgenException('Invalid Dart key identifier "${request.key}".');
    }
  }

  void _validateDependencies(TomgenProject project) {
    final pubspec = File(p.join(project.root.path, 'pubspec.yaml'));
    final Object? document;
    try {
      document = loadYaml(pubspec.readAsStringSync());
    } on Object catch (error) {
      throw TomgenException('Failed to parse ${pubspec.path}: $error');
    }
    if (document is! YamlMap) {
      throw TomgenException('${pubspec.path} must contain a YAML map.');
    }
    final problems = <String>[];
    final dependencies = _dependencySection(document, 'dependencies', problems);
    final devDependencies = _dependencySection(
      document,
      'dev_dependencies',
      problems,
    );
    final missingRegular = <String>[];
    final missingDev = <String>[];
    _checkDependency(
      name: 'tomg',
      expected: dependencies,
      other: devDependencies,
      section: 'dependencies',
      missing: missingRegular,
      problems: problems,
    );
    for (final name in <String>['tomgen', 'build_runner']) {
      _checkDependency(
        name: name,
        expected: devDependencies,
        other: dependencies,
        section: 'dev_dependencies',
        missing: missingDev,
        problems: problems,
      );
    }
    if (missingRegular.isNotEmpty) {
      problems.add('Run: dart pub add ${missingRegular.join(' ')}');
    }
    if (missingDev.isNotEmpty) {
      problems.add('Run: dart pub add --dev ${missingDev.join(' ')}');
    }
    if (problems.isNotEmpty) {
      throw TomgenException(
        'Dependency corrections required:\n'
        '${problems.map((item) => '- $item').join('\n')}',
      );
    }
  }

  Map<Object?, Object?> _dependencySection(
    YamlMap pubspec,
    String name,
    List<String> problems,
  ) {
    final raw = pubspec[name];
    if (raw == null) return const <Object?, Object?>{};
    if (raw is! YamlMap) {
      problems.add('$name must be a YAML map.');
      return const <Object?, Object?>{};
    }
    return raw;
  }

  void _checkDependency({
    required String name,
    required Map<Object?, Object?> expected,
    required Map<Object?, Object?> other,
    required String section,
    required List<String> missing,
    required List<String> problems,
  }) {
    if (expected.containsKey(name) && _validDependencySpec(expected[name])) {
      return;
    }
    if (expected.containsKey(name)) {
      problems.add('$name has an invalid specification in $section.');
    } else if (other.containsKey(name)) {
      problems.add('$name must be declared in $section.');
    } else {
      problems.add('$name is missing from $section.');
    }
    missing.add(name);
  }

  bool _validDependencySpec(Object? value) {
    if (value is String) return value.trim().isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return false;
  }

  String _readSource(File file, String relative) {
    try {
      return file.readAsStringSync();
    } on Object catch (error) {
      throw TomgenException('Failed to read TOML source "$relative": $error');
    }
  }

  TomgRegistryDocument _parseDocument(String content, String relative) {
    try {
      return TomgRegistryDocument.parse(content, source: relative);
    } on TomgDocumentException catch (error) {
      throw TomgenException(error.message);
    }
  }

  String _manifest({
    required String output,
    required String source,
    required String target,
    required String model,
    required String key,
  }) =>
      'version = 1\n'
      'output = ${jsonEncode(_portable(output))}\n\n'
      '[targets.$target]\n'
      'source = ${jsonEncode(_portable(source))}\n'
      'model = ${jsonEncode(model)}\n'
      'key = ${jsonEncode(key)}\n';

  void _planExact({
    required TomgenProject project,
    required String relative,
    required String content,
    required List<_PlannedFile> changes,
    required List<String> reused,
    required List<String> conflicts,
  }) {
    final path = resolveContainedPath(
      root: project.root,
      relativePath: relative,
      description: 'initializer destination "$relative"',
      requireDescendant: true,
    );
    final file = File(path);
    final proposed = utf8.encode(content);
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      conflicts.add('$relative exists and is not a regular file.');
      return;
    }
    final original = file.existsSync() ? file.readAsBytesSync() : null;
    if (original != null && _bytesEqual(original, proposed)) {
      reused.add(relative);
      return;
    }
    if (original != null) {
      conflicts.add('$relative differs from the requested scaffold.');
      return;
    }
    changes.add(
      _PlannedFile(
        relative: relative,
        file: file,
        original: null,
        proposed: proposed,
      ),
    );
  }

  _BuildPlan? _planBuildYaml(
    TomgenProject project,
    String sourceRelative,
    String sourcePath,
  ) {
    final libPath = p.join(project.root.path, 'lib');
    if (p.isWithin(libPath, sourcePath)) return null;
    final relative = 'build.yaml';
    final file = File(p.join(project.root.path, relative));
    if (!file.existsSync()) {
      final content =
          'targets:\n'
          '  \$default:\n'
          '    sources:\n'
          '      - \$package\$\n'
          '      - lib/**\n'
          '      - ${_portable(sourceRelative)}\n';
      return _BuildPlan.change(
        _PlannedFile(
          relative: relative,
          file: file,
          original: null,
          proposed: utf8.encode(content),
        ),
      );
    }
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return const _BuildPlan.conflict(
        'build.yaml exists and is not a regular file.',
      );
    }
    final original = file.readAsBytesSync();
    final content = utf8.decode(original);
    final Object? root;
    try {
      root = loadYaml(content);
    } on Object catch (error) {
      return _BuildPlan.conflict('build.yaml cannot be parsed: $error');
    }
    if (root is! YamlMap) {
      return const _BuildPlan.conflict('build.yaml must contain a YAML map.');
    }
    final editor = YamlEditor(content);
    try {
      final targets = root['targets'];
      if (targets == null) {
        editor.update(
          <Object>['targets'],
          <String, Object>{
            r'$default': <String, Object>{
              'sources': <String>[r'$package$', 'lib/**', sourceRelative],
            },
          },
        );
      } else if (targets is! YamlMap) {
        return const _BuildPlan.conflict(
          'build.yaml targets must be a YAML map; add the source manually.',
        );
      } else {
        final defaultTarget = targets[r'$default'];
        if (defaultTarget == null) {
          editor.update(
            <Object>['targets', r'$default'],
            <String, Object>{
              'sources': <String>[r'$package$', 'lib/**', sourceRelative],
            },
          );
        } else if (defaultTarget is! YamlMap) {
          return const _BuildPlan.conflict(
            'build.yaml targets.\$default must be a YAML map; add the source manually.',
          );
        } else {
          final sources = defaultTarget['sources'];
          if (sources == null) {
            editor.update(
              <Object>['targets', r'$default', 'sources'],
              <String>[r'$package$', 'lib/**', sourceRelative],
            );
          } else if (sources is! YamlList ||
              sources.any((item) => item is! String)) {
            return _BuildPlan.conflict(
              'build.yaml targets.\$default.sources must be a string list; '
              'add "${_portable(sourceRelative)}" manually.',
            );
          } else {
            final patterns = sources.cast<String>();
            if (_isCovered(patterns, sourceRelative)) {
              return const _BuildPlan.reused();
            }
            editor.appendToList(<Object>[
              'targets',
              r'$default',
              'sources',
            ], _portable(sourceRelative));
          }
        }
      }
    } on Object catch (error) {
      return _BuildPlan.conflict(
        'build.yaml cannot be safely edited; add '
        '"${_portable(sourceRelative)}" manually: $error',
      );
    }
    return _BuildPlan.change(
      _PlannedFile(
        relative: relative,
        file: file,
        original: original,
        proposed: utf8.encode(editor.toString()),
      ),
    );
  }

  bool _isCovered(List<String> patterns, String source) {
    final portable = _portable(source);
    var included = false;
    for (final raw in patterns) {
      if (raw == r'$package$') continue;
      final excluded = raw.startsWith('!');
      final pattern = excluded ? raw.substring(1) : raw;
      final matches = Glob(_portable(pattern)).matches(portable);
      if (matches) {
        if (excluded) return false;
        included = true;
      }
    }
    return included;
  }

  String _normalizeRelative(String value) {
    if (value.trim().isEmpty) throw TomgenException('Paths must not be empty.');
    if (p.isAbsolute(value)) {
      throw TomgenException('Paths must be package-relative.');
    }
    return p.normalize(value);
  }

  String _portable(String value) => value.replaceAll('\\', '/');
}

final class InitializationPlan {
  const InitializationPlan._({
    required this.project,
    required this._changes,
    required this.reused,
  });

  final TomgenProject project;
  final List<_PlannedFile> _changes;
  final List<String> reused;

  InitializationResult commit({InitializationHook? hook}) {
    final id = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
    final temporary = <_PlannedFile, File>{};
    final backups = <_PlannedFile, File>{};
    final installed = <_PlannedFile>[];
    try {
      for (final change in _changes) {
        change.file.parent.createSync(recursive: true);
        final temp = File('${change.file.path}.tomgen-init.tmp.$id');
        temp.writeAsBytesSync(change.proposed, flush: true);
        temporary[change] = temp;
      }
      hook?.call('prepared');
      for (final change in _changes) {
        final current = change.file.existsSync()
            ? change.file.readAsBytesSync()
            : null;
        if (!_nullableBytesEqual(current, change.original)) {
          throw TomgenException(
            'Destination changed during initialization: ${change.relative}',
          );
        }
      }
      for (final change in _changes) {
        if (change.file.existsSync()) {
          final backup = File('${change.file.path}.tomgen-init.bak.$id');
          change.file.renameSync(backup.path);
          backups[change] = backup;
        }
      }
      hook?.call('backed-up');
      for (final change in _changes) {
        temporary[change]!.renameSync(change.file.path);
        installed.add(change);
        hook?.call('installed:${change.relative}');
      }
      hook?.call('installed');
      for (final backup in backups.values) {
        if (backup.existsSync()) backup.deleteSync();
      }
    } on Object catch (error) {
      for (final change in installed.reversed) {
        if (change.file.existsSync()) change.file.deleteSync();
      }
      for (final entry in backups.entries) {
        if (entry.value.existsSync()) {
          entry.value.renameSync(entry.key.file.path);
        }
      }
      if (error is TomgenException) rethrow;
      throw TomgenException('Failed to initialize project files: $error');
    } finally {
      for (final file in temporary.values) {
        if (file.existsSync()) file.deleteSync();
      }
      for (final file in backups.values) {
        if (file.existsSync()) file.deleteSync();
      }
    }
    final created = _changes.map((change) => change.relative).toList()..sort();
    return InitializationResult(
      project: project,
      created: List<String>.unmodifiable(created),
      reused: reused,
    );
  }
}

final class _PlannedFile {
  const _PlannedFile({
    required this.relative,
    required this.file,
    required this.original,
    required this.proposed,
  });

  final String relative;
  final File file;
  final List<int>? original;
  final List<int> proposed;
}

final class _BuildPlan {
  const _BuildPlan.change(this.change) : conflict = null;
  const _BuildPlan.conflict(this.conflict) : change = null;
  const _BuildPlan.reused() : change = null, conflict = null;

  final _PlannedFile? change;
  final String? conflict;
}

bool _nullableBytesEqual(List<int>? left, List<int>? right) {
  if (left == null || right == null) return left == right;
  return _bytesEqual(left, right);
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

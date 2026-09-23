import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('starter and custom init build compilable registries', () async {
    final workspace = _workspaceRoot();
    for (final fixture in <_Fixture>[
      const _Fixture(
        name: 'starter',
        initArguments: <String>['init'],
        target: 'items',
      ),
      const _Fixture(
        name: 'custom',
        source: '''
[primary]
code = "primary"
enabled = true
''',
        initArguments: <String>[
          'init',
          '--source',
          'config/services.toml',
          '--target',
          'services',
          '--model',
          'Service',
          '--key',
          'code',
        ],
        target: 'services',
      ),
    ]) {
      final root = Directory.systemTemp.createTempSync(
        'tomgen_init_${fixture.name}_',
      );
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      Directory(p.join(root.path, 'lib')).createSync();
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: tomgen_init_${fixture.name}
environment:
  sdk: ^3.12.2
dependencies:
  tomg:
    path: ${p.join(workspace.path, 'tomg')}
dev_dependencies:
  tomgen:
    path: ${p.join(workspace.path, 'tomgen')}
  build_runner: ^2.16.1
dependency_overrides:
  tomg:
    path: ${p.join(workspace.path, 'tomg')}
''');
      if (fixture.source != null) {
        final source = File(p.join(root.path, 'config/services.toml'));
        source.parent.createSync(recursive: true);
        source.writeAsStringSync(fixture.source!);
      }

      await _run(root, <String>['pub', 'get']);
      await _run(root, <String>['run', 'tomgen', ...fixture.initArguments]);
      expect(
        File(p.join(root.path, 'pubspec.yaml')).readAsStringSync(),
        isNot(contains('assets:')),
      );
      expect(
        File(p.join(root.path, 'build.yaml')).readAsStringSync(),
        contains(fixture.sourcePath),
      );
      if (fixture.source != null) {
        expect(
          File(p.join(root.path, fixture.sourcePath)).readAsStringSync(),
          fixture.source,
        );
      }
      expect(
        Directory(p.join(root.path, 'lib'))
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => p.extension(file.path) == '.toml'),
        isEmpty,
      );

      await _run(root, <String>['run', 'tomgen', 'build']);
      final model = File(
        p.join(root.path, 'lib/generated/${fixture.target}.dart'),
      );
      final registry = File(
        p.join(root.path, 'lib/generated/${fixture.target}.g.dart'),
      );
      expect(model.existsSync(), isTrue, reason: fixture.name);
      expect(registry.existsSync(), isTrue, reason: fixture.name);
      expect(registry.readAsStringSync(), contains('const Map<'));
      await _run(root, <String>['analyze']);
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}

Directory _workspaceRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    if (Directory(p.join(directory.path, 'tomg')).existsSync() &&
        Directory(p.join(directory.path, 'tomgen')).existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (p.equals(parent.path, directory.path)) {
      throw StateError('Could not locate the dart-tomg workspace.');
    }
    directory = parent;
  }
}

Future<void> _run(Directory root, List<String> arguments) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    arguments,
    workingDirectory: root.path,
  );
  if (result.exitCode != 0) {
    fail(
      '${arguments.join(' ')} failed with ${result.exitCode}\n'
      'stdout:\n${result.stdout}\n'
      'stderr:\n${result.stderr}',
    );
  }
}

final class _Fixture {
  const _Fixture({
    required this.name,
    required this.initArguments,
    required this.target,
    this.source,
  });

  final String name;
  final String? source;
  final List<String> initArguments;
  final String target;

  String get sourcePath =>
      source == null ? 'config/items.toml' : 'config/services.toml';
}

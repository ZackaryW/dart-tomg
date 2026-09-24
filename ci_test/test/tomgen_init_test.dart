import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'starter and custom init build compilable registries',
    () async {
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

      await _verifyWorkspaceExternalSource(workspace);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<void> _verifyWorkspaceExternalSource(Directory repository) async {
  final workspace = Directory.systemTemp.createTempSync(
    'tomgen_external_workspace_',
  );
  addTearDown(() {
    if (workspace.existsSync()) workspace.deleteSync(recursive: true);
  });
  final consumer = Directory(p.join(workspace.path, 'apps', 'consumer'))
    ..createSync(recursive: true);
  Directory(
    p.join(consumer.path, 'lib', 'generated'),
  ).createSync(recursive: true);
  Directory(p.join(consumer.path, 'bin')).createSync();
  File(p.join(workspace.path, 'pubspec.yaml')).writeAsStringSync('''
name: external_source_workspace
publish_to: none
environment:
  sdk: ^3.12.2
workspace:
  - apps/consumer
''');
  File(p.join(consumer.path, 'pubspec.yaml')).writeAsStringSync('''
name: external_source_consumer
environment:
  sdk: ^3.12.2
resolution: workspace
dependencies:
  tomg:
    path: ${p.join(repository.path, 'tomg')}
dev_dependencies:
  tomgen:
    path: ${p.join(repository.path, 'tomgen')}
  build_runner: ^2.16.1
dependency_overrides:
  tomg:
    path: ${p.join(repository.path, 'tomg')}
''');
  final source = File(p.join(workspace.path, 'config', 'tenants.toml'));
  source.parent.createSync(recursive: true);
  const originalSource = '''
[__tomg]
obfuscate = ["code"]

[primary]
code = "tenant-code"
name = "Primary"
''';
  source.writeAsStringSync(originalSource);
  File(p.join(consumer.path, 'g.toml')).writeAsStringSync('''
version = 1
output = "lib/generated"
[targets.tenants]
source = "../../config/tenants.toml"
model = "Tenant"
key = "code"
''');
  File(p.join(consumer.path, 'bin', 'check.dart')).writeAsStringSync('''
import 'package:external_source_consumer/generated/tenants.dart';
import 'package:tomg/tomg.dart';

void main() {
  final tenant = tenantRegistry[TomgCodec.encodeString('tenant-code')];
  if (tenant == null || tenant.deobf.code != 'tenant-code') {
    throw StateError('External registry lookup failed.');
  }
  if (tenantRegistry[TomgCodec.encodeString('unknown')] != null) {
    throw StateError('Unknown external registry key unexpectedly resolved.');
  }
}
''');

  await _run(workspace, <String>['pub', 'get']);
  await _run(consumer, <String>['run', 'tomgen', 'build']);
  final model = File(p.join(consumer.path, 'lib', 'generated', 'tenants.dart'));
  final registry = File(
    p.join(consumer.path, 'lib', 'generated', 'tenants.g.dart'),
  );
  final generatedModel = model.readAsStringSync();
  expect(generatedModel, contains('"../../config/tenants.toml"'));
  expect(generatedModel, contains('sha256:'));
  expect(File(p.join(consumer.path, 'build.yaml')).existsSync(), isFalse);
  expect(
    File(p.join(consumer.path, 'pubspec.yaml')).readAsStringSync(),
    isNot(contains('assets:')),
  );
  await _run(consumer, <String>['analyze']);
  await _run(consumer, <String>['run', 'bin/check.dart']);

  await _run(consumer, <String>['run', 'build_runner', 'clean']);
  if (registry.existsSync()) registry.deleteSync();
  await _run(consumer, <String>['run', 'build_runner', 'build']);
  expect(registry.existsSync(), isTrue);

  source.writeAsStringSync(originalSource.replaceFirst('Primary', 'Changed'));
  await _run(consumer, <String>['run', 'build_runner', 'clean']);
  final stale = await _runFailure(consumer, <String>[
    'run',
    'build_runner',
    'build',
  ]);
  expect(
    '${stale.stdout}\n${stale.stderr}',
    allOf(contains('stale'), contains('dart run tomgen build')),
  );
  expect(registry.existsSync(), isFalse);

  source.writeAsStringSync(originalSource);
  await _run(consumer, <String>['run', 'tomgen', 'generate']);
  source.deleteSync();
  await _run(consumer, <String>['run', 'build_runner', 'clean']);
  final missing = await _runFailure(consumer, <String>[
    'run',
    'build_runner',
    'build',
  ]);
  expect(
    '${missing.stdout}\n${missing.stderr}',
    allOf(contains('does not exist'), contains('dart run tomgen build')),
  );
  expect(registry.existsSync(), isFalse);

  source.writeAsStringSync(originalSource);
  await _run(consumer, <String>['run', 'tomgen', 'generate']);
  final refreshedModel = model.readAsStringSync();
  final outside = File(
    p.join(
      Directory.systemTemp.path,
      'tomgen_outside_${workspace.hashCode}.toml',
    ),
  )..writeAsStringSync(originalSource);
  addTearDown(() {
    if (outside.existsSync()) outside.deleteSync();
  });
  final outsideRelative = p
      .relative(outside.path, from: consumer.path)
      .replaceAll('\\', '/');
  model.writeAsStringSync(
    refreshedModel.replaceFirst(
      '"../../config/tenants.toml"',
      '"$outsideRelative"',
    ),
  );
  await _run(consumer, <String>['run', 'build_runner', 'clean']);
  final escaped = await _runFailure(consumer, <String>[
    'run',
    'build_runner',
    'build',
  ]);
  expect(
    '${escaped.stdout}\n${escaped.stderr}',
    allOf(contains('escapes'), contains('dart run tomgen build')),
  );
  expect(registry.existsSync(), isFalse);
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

Future<ProcessResult> _runFailure(
  Directory root,
  List<String> arguments,
) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    arguments,
    workingDirectory: root.path,
  );
  if (result.exitCode == 0) {
    fail('${arguments.join(' ')} unexpectedly succeeded.');
  }
  return result;
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

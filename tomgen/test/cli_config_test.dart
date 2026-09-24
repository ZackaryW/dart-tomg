import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tomgen/src/cli/app.dart';
import 'package:tomgen/src/cli/config.dart';
import 'package:tomgen/src/cli/errors.dart';
import 'package:tomgen/src/cli/project.dart';

import 'test_support.dart';

void main() {
  group('command parsing', () {
    test('recognizes commands, help, and forwarded build arguments', () {
      expect(TomgenInvocation.parse(<String>[]).command, TomgenCommand.help);
      expect(
        TomgenInvocation.parse(<String>['generate']).command,
        TomgenCommand.generate,
      );
      expect(
        TomgenInvocation.parse(<String>['clean']).command,
        TomgenCommand.clean,
      );
      final build = TomgenInvocation.parse(<String>[
        'build',
        '--',
        '--delete-conflicting-outputs',
      ]);
      expect(build.command, TomgenCommand.build);
      expect(build.forwardedArguments, <String>[
        '--delete-conflicting-outputs',
      ]);
      final starter = TomgenInvocation.parse(<String>['init']);
      expect(starter.command, TomgenCommand.init);
      expect(starter.initRequest!.source, 'config/items.toml');
      expect(starter.initRequest!.createStarterSource, isTrue);

      final custom = TomgenInvocation.parse(<String>[
        'init',
        '--source',
        'config/services.toml',
        '--target=services',
        '--model',
        'Service',
        '--key',
        'id',
        '--output',
        'lib/config',
      ]).initRequest!;
      expect(custom.source, 'config/services.toml');
      expect(custom.target, 'services');
      expect(custom.model, 'Service');
      expect(custom.key, 'id');
      expect(custom.output, 'lib/config');
      expect(custom.createStarterSource, isFalse);
    });

    test('rejects unknown commands and misplaced forwarded arguments', () {
      expect(
        () => TomgenInvocation.parse(<String>['wat']),
        throwsA(isA<TomgenException>()),
      );
      expect(
        () => TomgenInvocation.parse(<String>['generate', '--', 'extra']),
        throwsA(isA<TomgenException>()),
      );
      expect(
        () => TomgenInvocation.parse(<String>['init', '--', 'extra']),
        throwsA(isA<TomgenException>()),
      );
      expect(
        () => TomgenInvocation.parse(<String>['init', 'extra']),
        throwsA(isA<TomgenException>()),
      );
      expect(
        () => TomgenInvocation.parse(<String>['init', '--wat', 'value']),
        throwsA(isA<TomgenException>()),
      );
      expect(
        () => TomgenInvocation.parse(<String>[
          'init',
          '--source=a.toml',
          '--source=b.toml',
          '--target=x',
          '--model=X',
          '--key=id',
        ]),
        throwsA(isA<TomgenException>()),
      );
      for (final omitted in <String>['source', 'target', 'model', 'key']) {
        final arguments = <String>['init'];
        final values = <String, String>{
          'source': 'config/x.toml',
          'target': 'x',
          'model': 'X',
          'key': 'id',
        };
        for (final entry in values.entries) {
          if (entry.key != omitted) {
            arguments.add('--${entry.key}=${entry.value}');
          }
        }
        expect(
          () => TomgenInvocation.parse(arguments),
          throwsA(isA<TomgenException>()),
          reason: 'missing --$omitted',
        );
      }
      expect(
        TomgenInvocation.parse(<String>['init', '--help']).command,
        TomgenCommand.help,
      );
    });
  });

  test('shared name validators match manifest rules', () {
    for (final valid in <String>['items', 'api_endpoints', 'x1']) {
      expect(isTomgenTargetName(valid), isTrue, reason: valid);
    }
    for (final invalid in <String>['Items', 'api-endpoints', '_items', '']) {
      expect(isTomgenTargetName(invalid), isFalse, reason: invalid);
    }
    for (final valid in <String>['Item', 'id', r'$value', '_private']) {
      expect(isDartIdentifier(valid), isTrue, reason: valid);
    }
    for (final invalid in <String>['class', 'two words', '1item', '']) {
      expect(isDartIdentifier(invalid), isFalse, reason: invalid);
    }
  });

  group('package discovery', () {
    late TestPackage package;

    setUp(() => package = TestPackage.create(name: 'nested_package'));
    tearDown(() => package.dispose());

    test('loads root and nested working directories', () {
      final nested = Directory(p.join(package.root.path, 'tool', 'nested'))
        ..createSync(recursive: true);
      expect(
        TomgenProject.discover(package.root).packageName,
        'nested_package',
      );
      expect(
        TomgenProject.discover(nested).root.resolveSymbolicLinksSync(),
        package.root.resolveSymbolicLinksSync(),
      );
      expect(
        TomgenProject.discover(nested).sourceBoundary.path,
        package.root.resolveSymbolicLinksSync(),
      );
    });

    test('reports missing and malformed pubspec files', () {
      final unrelated = Directory.systemTemp.createTempSync('tomgen_none_');
      addTearDown(() => unrelated.deleteSync(recursive: true));
      expect(
        () => TomgenProject.discover(unrelated),
        throwsA(isA<TomgenException>()),
      );
      package.write('pubspec.yaml', 'name: [broken');
      expect(
        () => TomgenProject.discover(package.root),
        throwsA(isA<TomgenException>()),
      );
    });

    test('matches literal and glob workspace members only', () {
      final workspace = Directory.systemTemp.createTempSync(
        'tomgen_workspace_members_',
      );
      final outside = Directory.systemTemp.createTempSync(
        'tomgen_workspace_member_outside_',
      );
      addTearDown(() {
        if (workspace.existsSync()) workspace.deleteSync(recursive: true);
        if (outside.existsSync()) outside.deleteSync(recursive: true);
      });
      final app = Directory(p.join(workspace.path, 'packages', 'app'))
        ..createSync(recursive: true);
      File(p.join(app.path, 'pubspec.yaml')).writeAsStringSync('''
name: workspace_app
environment:
  sdk: ^3.12.2
''');
      final workspacePubspec = File(p.join(workspace.path, 'pubspec.yaml'));

      void writeMembers(List<String> members) {
        final memberLines = members
            .map((member) => "  - '${member.replaceAll("'", "''")}'")
            .join('\n');
        workspacePubspec.writeAsStringSync('''
name: enclosing_workspace
publish_to: none
environment:
  sdk: ^3.12.2
workspace:
$memberLines
''');
      }

      for (final member in <String>['packages/app', 'packages/*']) {
        writeMembers(<String>[member]);
        expect(
          TomgenProject.discover(app).sourceBoundary.path,
          workspace.resolveSymbolicLinksSync(),
          reason: member,
        );
      }

      for (final members in <List<String>>[
        <String>['apps/*'],
        <String>['packages/['],
        <String>[p.join(workspace.path, 'packages', '*')],
        <String>[r'C:\packages\*'],
      ]) {
        writeMembers(members);
        expect(
          TomgenProject.discover(app).sourceBoundary.path,
          app.resolveSymbolicLinksSync(),
          reason: members.single,
        );
      }

      final externalApp = Directory(p.join(outside.path, 'app'))..createSync();
      File(p.join(externalApp.path, 'pubspec.yaml')).writeAsStringSync('''
name: linked_app
environment:
  sdk: ^3.12.2
''');
      writeMembers(<String>['packages/*']);
      final link = Link(p.join(workspace.path, 'packages', 'linked'));
      link.createSync(externalApp.path);
      expect(
        TomgenProject.discover(Directory(link.path)).sourceBoundary.path,
        externalApp.resolveSymbolicLinksSync(),
      );
    });

    test('package configuration mapping verifies the requested identity', () {
      final root = Directory.systemTemp.createTempSync('tomgen_package_map_');
      addTearDown(() => root.deleteSync(recursive: true));
      final mapped = Directory(p.join(root.path, 'mapped'))..createSync();
      File(p.join(mapped.path, 'pubspec.yaml')).writeAsStringSync('''
name: actual_package
environment:
  sdk: ^3.12.2
''');
      final config = File(
        p.join(root.path, '.dart_tool', 'package_config.json'),
      );
      config.parent.createSync();
      config.writeAsStringSync('''
{"configVersion":2,"packages":[{"name":"requested_package","rootUri":"../mapped/","packageUri":"lib/"}]}
''');

      expect(
        () => locateConfiguredPackageRoot('requested_package', start: root),
        throwsA(
          isA<TomgenException>().having(
            (error) => error.message,
            'message',
            allOf(contains('requested_package'), contains('actual_package')),
          ),
        ),
      );
    });
  });

  group('g.toml', () {
    late TestPackage package;

    setUp(() {
      package = TestPackage.create();
      package.write(
        'config/items.toml',
        '[one]\nid = "one"\nstatus = "live"\n',
      );
    });
    tearDown(() => package.dispose());

    test('loads a strict multi-target manifest', () {
      package.write('config/other.toml', '[two]\nid = "two"\n');
      package.write('g.toml', '''
version = 1
output = "lib/generated"

[targets.items]
source = "config/items.toml"
model = "Item"
key = "id"

[targets.items.defaults]
enabled = true

[targets.items.enums.status]
name = "Status"
values = ["live", "disabled"]

[targets.other]
source = "config/other.toml"
model = "Other"
key = "id"
''');
      final config = TomgenConfig.load(TomgenProject.discover(package.root));
      expect(config.targets.map((target) => target.name), <String>[
        'items',
        'other',
      ]);
      expect(config.targets.first.defaults, <String, Object?>{'enabled': true});
      expect(config.targets.first.enums['status']!.name, 'Status');
      expect(config.outputRelative, p.join('lib', 'generated'));
    });

    test('rejects versions, unknown keys, missing keys, and invalid names', () {
      for (final manifest in <String>[
        'version = 2\noutput = "lib/generated"\n[targets.x]\nsource = "config/items.toml"\nmodel = "Item"\nkey = "id"\n',
        'version = 1\noutput = "lib/generated"\nwat = true\n[targets.x]\nsource = "config/items.toml"\nmodel = "Item"\nkey = "id"\n',
        'version = 1\noutput = "lib/generated"\n[targets.x]\nsource = "config/items.toml"\nmodel = "Item"\n',
        'version = 1\noutput = "lib/generated"\n[targets.Bad-Name]\nsource = "config/items.toml"\nmodel = "Item"\nkey = "id"\n',
        'version = 1\nversion = 1\noutput = "lib/generated"\n[targets.x]\nsource = "config/items.toml"\nmodel = "Item"\nkey = "id"\n',
        'version = 1\noutput = "lib/generated"\n[targets.x]\nsource = "config/items.toml"\nmodel = "Item"\nkey = "id"\n[targets.x.enums.status]\nname = "Status"\nvalues = []\n',
      ]) {
        package.write('g.toml', manifest);
        expect(
          () => TomgenConfig.load(TomgenProject.discover(package.root)),
          throwsA(isA<TomgenException>()),
          reason: manifest,
        );
      }
    });

    test(
      'rejects output and source paths escaping through traversal or links',
      () {
        package.write('g.toml', '''
version = 1
output = "../outside"
[targets.items]
source = "config/items.toml"
model = "Item"
key = "id"
''');
        expect(
          () => TomgenConfig.load(TomgenProject.discover(package.root)),
          throwsA(isA<TomgenException>()),
        );

        final outside = Directory.systemTemp.createTempSync('tomgen_outside_');
        addTearDown(() => outside.deleteSync(recursive: true));
        final link = Link(p.join(package.root.path, 'lib', 'linked'));
        link.createSync(outside.path);
        package.write('g.toml', '''
version = 1
output = "lib/linked"
[targets.items]
source = "config/items.toml"
model = "Item"
key = "id"
''');
        expect(
          () => TomgenConfig.load(TomgenProject.discover(package.root)),
          throwsA(isA<TomgenException>()),
        );
        expect(outside.listSync(), isEmpty);

        final outsideToml = File(p.join(outside.path, 'outside.toml'))
          ..writeAsStringSync('[x]\nid = "x"\n');
        package.write('g.toml', '''
version = 1
output = "lib/generated"
[targets.items]
source = "${p.relative(outsideToml.path, from: package.root.path).replaceAll('\\', '/')}"
model = "Item"
key = "id"
''');
        expect(
          () => TomgenConfig.load(TomgenProject.discover(package.root)),
          throwsA(isA<TomgenException>()),
        );

        final sourceLink = Link(
          p.join(package.root.path, 'config', 'escape.toml'),
        );
        sourceLink.createSync(outsideToml.path);
        package.write('g.toml', '''
version = 1
output = "lib/generated"
[targets.items]
source = "config/escape.toml"
model = "Item"
key = "id"
''');
        expect(
          () => TomgenConfig.load(TomgenProject.discover(package.root)),
          throwsA(isA<TomgenException>()),
        );
        expect(outsideToml.readAsStringSync(), contains('id = "x"'));
      },
    );

    test('accepts only workspace-contained external sources', () {
      final workspace = Directory.systemTemp.createTempSync(
        'tomgen_workspace_',
      );
      final outside = Directory.systemTemp.createTempSync('tomgen_external_');
      addTearDown(() {
        if (workspace.existsSync()) workspace.deleteSync(recursive: true);
        if (outside.existsSync()) outside.deleteSync(recursive: true);
      });
      final app = Directory(p.join(workspace.path, 'packages', 'app'))
        ..createSync(recursive: true);
      Directory(p.join(app.path, 'lib')).createSync();
      File(p.join(workspace.path, 'pubspec.yaml')).writeAsStringSync('''
name: enclosing_workspace
publish_to: none
environment:
  sdk: ^3.12.2
workspace:
  - packages/app
''');
      File(p.join(app.path, 'pubspec.yaml')).writeAsStringSync('''
name: workspace_app
environment:
  sdk: ^3.12.2
resolution: workspace
''');
      final shared = File(p.join(workspace.path, 'config', 'items.toml'));
      shared.parent.createSync(recursive: true);
      shared.writeAsStringSync('[one]\nid = "one"\n');
      void writeManifest(String source) {
        File(p.join(app.path, 'g.toml')).writeAsStringSync('''
version = 1
output = "lib/generated"
[targets.items]
source = "$source"
model = "Item"
key = "id"
''');
      }

      writeManifest('../../config/items.toml');
      final project = TomgenProject.discover(app);
      expect(
        project.sourceBoundary.resolveSymbolicLinksSync(),
        workspace.resolveSymbolicLinksSync(),
      );
      final target = TomgenConfig.load(project).targets.single;
      expect(target.isExternal, isTrue);
      expect(target.sourceRelative, p.join('..', '..', 'config', 'items.toml'));

      final outsideFile = File(p.join(outside.path, 'outside.toml'))
        ..writeAsStringSync('[one]\nid = "one"\n');
      writeManifest(p.relative(outsideFile.path, from: app.path));
      expect(() => TomgenConfig.load(project), throwsA(isA<TomgenException>()));

      final escape = Link(p.join(workspace.path, 'config', 'escape.toml'));
      escape.createSync(outsideFile.path);
      writeManifest('../../config/escape.toml');
      expect(() => TomgenConfig.load(project), throwsA(isA<TomgenException>()));
    });
  });
}

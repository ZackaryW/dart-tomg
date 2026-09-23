import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tomgen/src/cli/app.dart';
import 'package:tomgen/src/cli/errors.dart';
import 'package:tomgen/src/cli/initializer.dart';

import 'test_support.dart';

void main() {
  group('dependency validation', () {
    test('accepts supported dependency specification forms', () {
      final specifications = <String>[
        '^0.1.0',
        'workspace',
        '{ hosted: https://pub.dev, version: ^0.1.0 }',
        '{ git: https://example.test/package.git }',
        '{ path: ../package }',
      ];
      for (final specification in specifications) {
        final package = TestPackage.create(name: 'dependency_example');
        try {
          _writePubspec(
            package,
            tomg: specification,
            tomgen: specification,
            buildRunner: specification,
          );
          package.write('config/items.toml', '[one]\nid = "one"\n');
          final plan = TomgenInitializer().plan(
            package.root,
            const TomgenInitRequest(
              source: 'config/items.toml',
              target: 'items',
              model: 'Item',
              key: 'id',
              output: 'lib/generated',
              createStarterSource: false,
            ),
          );
          expect(plan.project.packageName, 'dependency_example');
        } finally {
          package.dispose();
        }
      }
    });

    test('reports missing, misplaced, and malformed dependencies', () {
      final missing = TestPackage.create();
      addTearDown(missing.dispose);
      expect(
        () => TomgenInitializer().plan(
          missing.root,
          const TomgenInitRequest.starter(),
        ),
        throwsA(
          isA<TomgenException>()
              .having(
                (error) => error.message,
                'message',
                contains('dart pub add tomg'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('dart pub add --dev tomgen build_runner'),
              ),
        ),
      );

      final misplaced = TestPackage.create();
      addTearDown(misplaced.dispose);
      misplaced.write('pubspec.yaml', '''
name: test_package
environment:
  sdk: ^3.12.2
dependencies:
  tomgen: ^0.1.0
  build_runner: ^2.16.1
dev_dependencies:
  tomg: ^0.1.0
''');
      expect(
        () => TomgenInitializer().plan(
          misplaced.root,
          const TomgenInitRequest.starter(),
        ),
        throwsA(
          isA<TomgenException>()
              .having(
                (error) => error.message,
                'message',
                contains('tomg must be declared in dependencies'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('tomgen must be declared in dev_dependencies'),
              ),
        ),
      );

      final malformed = TestPackage.create();
      addTearDown(malformed.dispose);
      malformed.write('pubspec.yaml', '''
name: test_package
environment:
  sdk: ^3.12.2
dependencies: [tomg]
dev_dependencies:
  tomgen:
  build_runner: ^2.16.1
''');
      expect(
        () => TomgenInitializer().plan(
          malformed.root,
          const TomgenInitRequest.starter(),
        ),
        throwsA(
          isA<TomgenException>()
              .having(
                (error) => error.message,
                'message',
                contains('dependencies must be a YAML map'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('tomgen has an invalid specification'),
              ),
        ),
      );
    });
  });

  group('request and source validation', () {
    late TestPackage package;

    setUp(() {
      package = TestPackage.create(name: 'initializer_example');
      _writePubspec(package);
      package.write('config/services.toml', '''
[primary]
id = "primary"
url = "https://example.test"
''');
    });
    tearDown(() => package.dispose());

    test('plans an existing source from a nested directory', () {
      final nested = Directory(p.join(package.root.path, 'tool', 'nested'))
        ..createSync(recursive: true);
      final result = TomgenInitializer().initialize(
        nested,
        const TomgenInitRequest(
          source: 'config/services.toml',
          target: 'services',
          model: 'Service',
          key: 'id',
          output: 'lib/config',
          createStarterSource: false,
        ),
      );
      expect(result.created, containsAll(<String>['build.yaml', 'g.toml']));
      expect(result.reused, contains('config/services.toml'));
      expect(package.read('g.toml'), contains('output = "lib/config"'));
      expect(package.read('g.toml'), contains('[targets.services]'));
    });

    test('rejects invalid names, files, TOML, keys, rows, and output', () {
      void expectFailure(TomgenInitRequest request, Matcher message) {
        expect(
          () => TomgenInitializer().plan(package.root, request),
          throwsA(
            isA<TomgenException>().having(
              (error) => error.message,
              'message',
              message,
            ),
          ),
        );
      }

      expectFailure(
        const TomgenInitRequest(
          source: 'config/services.toml',
          target: 'Bad-Target',
          model: 'Service',
          key: 'id',
          output: 'lib/generated',
          createStarterSource: false,
        ),
        contains('Invalid target'),
      );
      expectFailure(
        const TomgenInitRequest(
          source: 'config/services.toml',
          target: 'services',
          model: 'class',
          key: 'id',
          output: 'lib/generated',
          createStarterSource: false,
        ),
        contains('Invalid Dart model'),
      );
      expectFailure(
        const TomgenInitRequest(
          source: 'config/missing.toml',
          target: 'services',
          model: 'Service',
          key: 'id',
          output: 'lib/generated',
          createStarterSource: false,
        ),
        contains('does not exist'),
      );
      package.write('config/broken.toml', '[broken');
      expectFailure(
        const TomgenInitRequest(
          source: 'config/broken.toml',
          target: 'services',
          model: 'Service',
          key: 'id',
          output: 'lib/generated',
          createStarterSource: false,
        ),
        contains('Failed to parse TOML'),
      );
      package.write('config/no_key.toml', '[one]\nname = "one"\n');
      expectFailure(
        const TomgenInitRequest(
          source: 'config/no_key.toml',
          target: 'services',
          model: 'Service',
          key: 'id',
          output: 'lib/generated',
          createStarterSource: false,
        ),
        contains('key "id" is not a model field'),
      );
      package.write('config/uninferable.toml', '[one]\nid = []\n');
      expectFailure(
        const TomgenInitRequest(
          source: 'config/uninferable.toml',
          target: 'services',
          model: 'Service',
          key: 'id',
          output: 'lib/generated',
          createStarterSource: false,
        ),
        contains('empty list'),
      );
      expectFailure(
        const TomgenInitRequest(
          source: 'config/services.toml',
          target: 'services',
          model: 'Service',
          key: 'id',
          output: '../generated',
          createStarterSource: false,
        ),
        contains('escapes'),
      );
      expectFailure(
        const TomgenInitRequest(
          source: 'config/services.toml',
          target: 'services',
          model: 'Service',
          key: 'id',
          output: 'tool/generated',
          createStarterSource: false,
        ),
        contains('beneath lib'),
      );
    });

    test('rejects a source symlink escaping the package', () {
      final outside = Directory.systemTemp.createTempSync('tomgen_init_out_');
      addTearDown(() => outside.deleteSync(recursive: true));
      final source = File(p.join(outside.path, 'outside.toml'))
        ..writeAsStringSync('[one]\nid = "one"\n');
      Link(
        p.join(package.root.path, 'config', 'escape.toml'),
      ).createSync(source.path);
      expect(
        () => TomgenInitializer().plan(
          package.root,
          const TomgenInitRequest(
            source: 'config/escape.toml',
            target: 'services',
            model: 'Service',
            key: 'id',
            output: 'lib/generated',
            createStarterSource: false,
          ),
        ),
        throwsA(isA<TomgenException>()),
      );
    });
  });

  group('build graph and conflicts', () {
    late TestPackage package;

    setUp(() {
      package = TestPackage.create();
      _writePubspec(package);
    });
    tearDown(() => package.dispose());

    test('creates external build input configuration without assets', () {
      final result = TomgenInitializer().initialize(
        package.root,
        const TomgenInitRequest.starter(),
      );
      expect(result.created, <String>[
        'build.yaml',
        'config/items.toml',
        'g.toml',
      ]);
      expect(package.read('build.yaml'), contains(r'$package$'));
      expect(package.read('build.yaml'), contains('config/items.toml'));
      expect(package.read('pubspec.yaml'), isNot(contains('assets:')));
    });

    test('preserves comments, ordering, and unrelated configuration', () {
      package.write('build.yaml', '''
# keep this comment
builders:
  custom:
    enabled: true
targets:
  \$default:
    # source comment
    sources:
      - \$package\$
      - lib/**
''');
      TomgenInitializer().initialize(
        package.root,
        const TomgenInitRequest.starter(),
      );
      final build = package.read('build.yaml');
      expect(build, contains('# keep this comment'));
      expect(build, contains('# source comment'));
      expect(build, contains('custom:'));
      expect(build, contains('config/items.toml'));
      expect(build.indexOf('builders:'), lessThan(build.indexOf('targets:')));
    });

    test('reuses exact and glob source coverage without rewriting', () async {
      for (final coverage in <String>['config/items.toml', 'config/**']) {
        package.write('build.yaml', '''
targets:
  \$default:
    sources:
      - \$package\$
      - lib/**
      - $coverage
''');
        final build = File(p.join(package.root.path, 'build.yaml'));
        final modified = build.lastModifiedSync();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final result = TomgenInitializer().initialize(
          package.root,
          const TomgenInitRequest.starter(),
        );
        expect(result.reused, contains('build.yaml'));
        expect(build.lastModifiedSync(), modified);
        File(p.join(package.root.path, 'g.toml')).deleteSync();
        File(p.join(package.root.path, 'config/items.toml')).deleteSync();
      }
    });

    test('reports every scaffold conflict without changing files', () {
      package.write('g.toml', 'user manifest\n');
      package.write('config/items.toml', '[mine]\nid = "mine"\n');
      package.write('build.yaml', '''
targets:
  \$default:
    sources: { include: config/** }
''');
      final before = <String, List<int>>{
        for (final path in <String>[
          'g.toml',
          'config/items.toml',
          'build.yaml',
        ])
          path: File(p.join(package.root.path, path)).readAsBytesSync(),
      };
      expect(
        () => TomgenInitializer().plan(
          package.root,
          const TomgenInitRequest.starter(),
        ),
        throwsA(
          isA<TomgenException>()
              .having((error) => error.message, 'message', contains('g.toml'))
              .having(
                (error) => error.message,
                'message',
                contains('config/items.toml'),
              )
              .having(
                (error) => error.message,
                'message',
                contains(r'$default.sources'),
              ),
        ),
      );
      for (final entry in before.entries) {
        expect(
          File(p.join(package.root.path, entry.key)).readAsBytesSync(),
          entry.value,
        );
      }
    });
  });

  group('transaction and CLI', () {
    late TestPackage package;

    setUp(() {
      package = TestPackage.create();
      _writePubspec(package);
    });
    tearDown(() => package.dispose());

    test('rolls back files and temporary state after an injected failure', () {
      final initializer = TomgenInitializer(
        hook: (stage) {
          if (stage == 'installed:g.toml') throw StateError('injected');
        },
      );
      expect(
        () => initializer.initialize(
          package.root,
          const TomgenInitRequest.starter(),
        ),
        throwsA(isA<TomgenException>()),
      );
      expect(File(p.join(package.root.path, 'g.toml')).existsSync(), isFalse);
      expect(
        File(p.join(package.root.path, 'config/items.toml')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(package.root.path, 'build.yaml')).existsSync(),
        isFalse,
      );
      expect(
        package.root
            .listSync(recursive: true)
            .map((entry) => entry.path)
            .where((path) => path.contains('.tomgen-init.')),
        isEmpty,
      );
    });

    test('restores an existing build file after a late failure', () {
      const original = '''
# existing configuration
targets:
  \$default:
    sources:
      - \$package\$
      - lib/**
''';
      package.write('build.yaml', original);
      final initializer = TomgenInitializer(
        hook: (stage) {
          if (stage == 'installed:build.yaml') throw StateError('injected');
        },
      );
      expect(
        () => initializer.initialize(
          package.root,
          const TomgenInitRequest.starter(),
        ),
        throwsA(isA<TomgenException>()),
      );
      expect(package.read('build.yaml'), original);
      expect(File(p.join(package.root.path, 'g.toml')).existsSync(), isFalse);
      expect(
        File(p.join(package.root.path, 'config/items.toml')).existsSync(),
        isFalse,
      );
    });

    test('rejects destination drift after planning without deleting it', () {
      final plan = TomgenInitializer().plan(
        package.root,
        const TomgenInitRequest.starter(),
      );
      final drift = File(p.join(package.root.path, 'g.toml'));
      expect(
        () => plan.commit(
          hook: (stage) {
            if (stage == 'prepared') drift.writeAsStringSync('concurrent\n');
          },
        ),
        throwsA(isA<TomgenException>()),
      );
      expect(drift.readAsStringSync(), 'concurrent\n');
      expect(
        File(p.join(package.root.path, 'config/items.toml')).existsSync(),
        isFalse,
      );
    });

    test('CLI initializes from a nested directory and is idempotent', () async {
      final nested = Directory(p.join(package.root.path, 'tool', 'nested'))
        ..createSync(recursive: true);
      final firstOut = StringBuffer();
      final firstErr = StringBuffer();
      expect(
        await TomgenApp(
          workingDirectory: nested,
          out: firstOut,
          err: firstErr,
        ).run(<String>['init']),
        0,
        reason: firstErr.toString(),
      );
      expect(firstOut.toString(), contains(package.root.path));
      expect(firstOut.toString(), contains('dart run tomgen build'));
      final files = <File>[
        File(p.join(package.root.path, 'g.toml')),
        File(p.join(package.root.path, 'config/items.toml')),
        File(p.join(package.root.path, 'build.yaml')),
      ];
      final modified = <DateTime>[
        for (final file in files) file.lastModifiedSync(),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final secondOut = StringBuffer();
      expect(
        await TomgenApp(
          workingDirectory: nested,
          out: secondOut,
          err: StringBuffer(),
        ).run(<String>['init']),
        0,
      );
      expect(secondOut.toString(), contains('Reused:'));
      expect(<DateTime>[
        for (final file in files) file.lastModifiedSync(),
      ], modified);
      expect(
        Directory(p.join(package.root.path, 'lib/generated')).existsSync(),
        isFalse,
      );
      expect(
        File(
          p.join(package.root.path, '.dart_tool/tomgen/manifest.json'),
        ).existsSync(),
        isFalse,
      );
    });

    test('CLI reports preflight failures without writing', () async {
      package.write('g.toml', 'mine\n');
      final err = StringBuffer();
      expect(
        await TomgenApp(
          workingDirectory: package.root,
          out: StringBuffer(),
          err: err,
        ).run(<String>['init']),
        1,
      );
      expect(err.toString(), contains('Initialization conflicts'));
      expect(package.read('g.toml'), 'mine\n');
      expect(
        File(p.join(package.root.path, 'config/items.toml')).existsSync(),
        isFalse,
      );
    });
  });
}

void _writePubspec(
  TestPackage package, {
  String tomg = '^0.1.0',
  String tomgen = '^0.1.0',
  String buildRunner = '^2.16.1',
}) {
  package.write('pubspec.yaml', '''
name: ${package.name}
environment:
  sdk: ^3.12.2
dependencies:
  tomg: $tomg
dev_dependencies:
  tomgen: $tomgen
  build_runner: $buildRunner
''');
}

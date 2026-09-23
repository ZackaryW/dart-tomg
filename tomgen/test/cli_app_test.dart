import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tomgen/src/cli/app.dart';

import 'test_support.dart';

void main() {
  late TestPackage package;

  setUp(() {
    package = TestPackage.create(name: 'cli_example');
    package.write('config/alpha.toml', '[one]\nid = "one"\n');
    package.write('config/beta.toml', '[two]\ncode = "two"\n');
    package.write('g.toml', '''
version = 1
output = "lib/generated"
[targets.alpha]
source = "config/alpha.toml"
model = "Alpha"
key = "id"
[targets.beta]
source = "config/beta.toml"
model = "Beta"
key = "code"
''');
  });
  tearDown(() => package.dispose());

  test('generate creates multiple models from a nested directory', () async {
    final nested = Directory(p.join(package.root.path, 'tool', 'nested'))
      ..createSync(recursive: true);
    final out = StringBuffer();
    final err = StringBuffer();
    final exit = await TomgenApp(
      workingDirectory: nested,
      out: out,
      err: err,
    ).run(<String>['generate']);
    expect(exit, 0, reason: err.toString());
    expect(
      File(p.join(package.root.path, 'lib/generated/alpha.dart')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(package.root.path, 'lib/generated/beta.dart')).existsSync(),
      isTrue,
    );
    expect(out.toString(), contains('Generated 2 model file(s)'));
    expect(err.toString(), isEmpty);
  });

  test('build runs generation first and forwards process arguments', () async {
    final calls = <String>[];
    final out = StringBuffer();
    final exit = await TomgenApp(
      workingDirectory: package.root,
      out: out,
      err: StringBuffer(),
      processRunner:
          (executable, arguments, {required workingDirectory}) async {
            expect(
              File(
                p.join(package.root.path, 'lib/generated/alpha.dart'),
              ).existsSync(),
              isTrue,
            );
            calls.add('$executable|$workingDirectory|${arguments.join('|')}');
            return 23;
          },
    ).run(<String>['build', '--', '--delete-conflicting-outputs']);
    expect(exit, 23);
    expect(calls, hasLength(1));
    expect(
      calls.single,
      contains('|run|build_runner|build|--delete-conflicting-outputs'),
    );
    expect(calls.single, contains(package.root.path));
    expect(out.toString(), contains('Running build_runner'));
  });

  test('phase-one failure blocks the build process', () async {
    File(p.join(package.root.path, 'g.toml')).deleteSync();
    var called = false;
    final err = StringBuffer();
    final exit = await TomgenApp(
      workingDirectory: package.root,
      out: StringBuffer(),
      err: err,
      processRunner:
          (executable, arguments, {required workingDirectory}) async {
            called = true;
            return 0;
          },
    ).run(<String>['build']);
    expect(exit, 1);
    expect(called, isFalse);
    expect(err.toString(), contains('Missing generation manifest'));
  });

  test('one invalid target leaves every model output unchanged', () async {
    package.write('config/beta.toml', '[two]\ncode = [["bad"]]\n');
    final err = StringBuffer();
    final exit = await TomgenApp(
      workingDirectory: package.root,
      out: StringBuffer(),
      err: err,
    ).run(<String>['generate']);
    expect(exit, 1);
    expect(err.toString(), contains('beta'));
    expect(
      File(p.join(package.root.path, 'lib/generated/alpha.dart')).existsSync(),
      isFalse,
    );
    expect(
      File(p.join(package.root.path, 'lib/generated/beta.dart')).existsSync(),
      isFalse,
    );
  });

  test('a structural TOML edit directly regenerates the model API', () async {
    final app = TomgenApp(
      workingDirectory: package.root,
      out: StringBuffer(),
      err: StringBuffer(),
    );
    expect(await app.run(<String>['generate']), 0);
    final generated = File(
      p.join(package.root.path, 'lib/generated/alpha.dart'),
    );
    final flat = generated.readAsStringSync();
    expect(flat, isNot(contains('AlphaDatabase')));

    package.write(
      'config/alpha.toml',
      '[one]\nid = "one"\ndatabase = { host = "db.example" }\n',
    );
    expect(await app.run(<String>['generate']), 0);
    final structured = generated.readAsStringSync();

    expect(structured, contains('class AlphaDatabase'));
    expect(structured, contains('final AlphaDatabase database;'));
    expect(structured, isNot(equals(flat)));
    expect(File(p.join(package.root.path, 'g.lock')).existsSync(), isFalse);
  });

  test(
    'help, unknown command, ownership conflict, and clean are reported',
    () async {
      final help = StringBuffer();
      expect(
        await TomgenApp(out: help, err: StringBuffer()).run(<String>['help']),
        0,
      );
      expect(help.toString(), contains('generate'));

      final unknown = StringBuffer();
      expect(
        await TomgenApp(out: StringBuffer(), err: unknown).run(<String>['wat']),
        1,
      );
      expect(unknown.toString(), contains('Unknown command'));

      package.write('lib/generated/alpha.dart', 'handwritten\n');
      final conflict = StringBuffer();
      expect(
        await TomgenApp(
          workingDirectory: package.root,
          out: StringBuffer(),
          err: conflict,
        ).run(<String>['generate']),
        1,
      );
      expect(conflict.toString(), contains('unowned'));
      File(p.join(package.root.path, 'lib/generated/alpha.dart')).deleteSync();

      await TomgenApp(
        workingDirectory: package.root,
        out: StringBuffer(),
        err: StringBuffer(),
      ).run(<String>['generate']);
      final cleanOut = StringBuffer();
      expect(
        await TomgenApp(
          workingDirectory: package.root,
          out: cleanOut,
          err: StringBuffer(),
        ).run(<String>['clean']),
        0,
      );
      expect(cleanOut.toString(), contains('Removed 2 tomgen model file(s)'));
    },
  );
}

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tomgen/src/cli/emitter.dart';
import 'package:tomgen/src/cli/errors.dart';
import 'package:tomgen/src/cli/ownership.dart';

import 'test_support.dart';

void main() {
  late TestPackage package;

  setUp(() => package = TestPackage.create());
  tearDown(() => package.dispose());

  String content(String name) => '$generatedNotice\nconst $name = 1;\n';

  test('tracks owned hashes and leaves unchanged files untouched', () async {
    final file = File(p.join(package.root.path, 'lib', 'generated', 'a.dart'));
    final store = OwnershipStore(package.root);
    final first = store.commit(<TomgenOutput>[
      TomgenOutput(file, content('a')),
    ]);
    expect(first.written, 1);
    expect(store.manifestFile.existsSync(), isTrue);
    final modified = file.lastModifiedSync();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final second = store.commit(<TomgenOutput>[
      TomgenOutput(file, content('a')),
    ]);
    expect(second.unchanged, 1);
    expect(file.lastModifiedSync(), modified);
  });

  test('rejects handwritten, untracked, and edited destinations', () {
    final file = package.write('lib/generated/a.dart', 'handwritten\n');
    expect(
      () => OwnershipStore(
        package.root,
      ).commit(<TomgenOutput>[TomgenOutput(file, content('a'))]),
      throwsA(isA<TomgenException>()),
    );
    expect(file.readAsStringSync(), 'handwritten\n');

    file.deleteSync();
    final store = OwnershipStore(package.root);
    store.commit(<TomgenOutput>[TomgenOutput(file, content('a'))]);
    file.writeAsStringSync('${content('a')}// edited\n');
    expect(
      () => store.commit(<TomgenOutput>[TomgenOutput(file, content('b'))]),
      throwsA(isA<TomgenException>()),
    );
    expect(file.readAsStringSync(), contains('// edited'));
  });

  test(
    'adopts an identical checked-in generated file without rewriting it',
    () {
      final file = package.write('lib/generated/a.dart', content('a'));
      final modified = file.lastModifiedSync();
      final store = OwnershipStore(package.root);
      final result = store.commit(<TomgenOutput>[
        TomgenOutput(file, content('a')),
      ]);
      expect(result.unchanged, 1);
      expect(file.lastModifiedSync(), modified);
      expect(store.manifestFile.existsSync(), isTrue);
    },
  );

  test('removes stale verified files on the next commit', () {
    final first = File(p.join(package.root.path, 'lib', 'generated', 'a.dart'));
    final second = File(
      p.join(package.root.path, 'lib', 'generated', 'b.dart'),
    );
    final store = OwnershipStore(package.root);
    store.commit(<TomgenOutput>[
      TomgenOutput(first, content('a')),
      TomgenOutput(second, content('b')),
    ]);
    final result = store.commit(<TomgenOutput>[
      TomgenOutput(second, content('b')),
    ]);
    expect(result.deleted, 1);
    expect(first.existsSync(), isFalse);
    expect(second.existsSync(), isTrue);
  });

  test(
    'restores prior outputs and manifest after an injected commit failure',
    () {
      final first = File(
        p.join(package.root.path, 'lib', 'generated', 'a.dart'),
      );
      final normal = OwnershipStore(package.root);
      normal.commit(<TomgenOutput>[TomgenOutput(first, content('before'))]);
      final manifestBefore = normal.manifestFile.readAsStringSync();

      final failing = OwnershipStore(
        package.root,
        hook: (stage) {
          if (stage == 'outputs-installed') throw StateError('injected');
        },
      );
      expect(
        () => failing.commit(<TomgenOutput>[
          TomgenOutput(first, content('after')),
        ]),
        throwsA(isA<TomgenException>()),
      );
      expect(first.readAsStringSync(), content('before'));
      expect(normal.manifestFile.readAsStringSync(), manifestBefore);
    },
  );

  test(
    'clean removes verified models but preserves g.dart and edited files',
    () {
      final model = File(
        p.join(package.root.path, 'lib', 'generated', 'a.dart'),
      );
      final generatedPart = package.write(
        'lib/generated/a.g.dart',
        '// build_runner output\n',
      );
      final unowned = package.write('lib/generated/manual.dart', 'manual\n');
      final store = OwnershipStore(package.root);
      store.commit(<TomgenOutput>[TomgenOutput(model, content('a'))]);
      final cleaned = store.clean();
      expect(cleaned.deleted, 1);
      expect(model.existsSync(), isFalse);
      expect(generatedPart.existsSync(), isTrue);
      expect(unowned.existsSync(), isTrue);
      expect(store.manifestFile.existsSync(), isFalse);

      store.commit(<TomgenOutput>[TomgenOutput(model, content('a'))]);
      model.writeAsStringSync('${content('a')}// edited\n');
      expect(() => store.clean(), throwsA(isA<TomgenException>()));
      expect(model.existsSync(), isTrue);
      expect(generatedPart.existsSync(), isTrue);
    },
  );

  test('removes a newly installed manifest after an injected failure', () {
    final file = File(
      p.join(package.root.path, 'lib', 'generated', 'new.dart'),
    );
    final failing = OwnershipStore(
      package.root,
      hook: (stage) {
        if (stage == 'manifest-installed') throw StateError('injected');
      },
    );
    expect(
      () => failing.commit(<TomgenOutput>[TomgenOutput(file, content('new'))]),
      throwsA(isA<TomgenException>()),
    );
    expect(file.existsSync(), isFalse);
    expect(failing.manifestFile.existsSync(), isFalse);
  });
}

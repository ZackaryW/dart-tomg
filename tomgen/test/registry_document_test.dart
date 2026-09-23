import 'package:test/test.dart';
import 'package:tomgen/src/registry_document.dart';

void main() {
  test('removes valid metadata and preserves registry rows', () {
    final document = TomgRegistryDocument.parse('''
[__tomg]
obfuscate = ["url"]
[one]
id = "one"
url = "https://example.com"
''', source: 'items.toml');
    expect(document.obfuscatedFields, <String>{'url'});
    expect(document.rows.keys, <String>['one']);
  });

  test('distinguishes absent metadata from an explicit empty declaration', () {
    expect(
      TomgRegistryDocument.parse(
        '[one]\nid = "one"',
        source: 'a',
      ).obfuscatedFields,
      isNull,
    );
    expect(
      TomgRegistryDocument.parse(
        '[__tomg]\nobfuscate = []\n[one]\nid = "one"',
        source: 'b',
      ).obfuscatedFields,
      isEmpty,
    );
  });

  test('rejects malformed, unknown, and duplicate metadata', () {
    for (final source in <String>[
      '__tomg = "bad"',
      '[__tomg]\nunknown = []',
      '[__tomg]\nobfuscate = ["url", "url"]',
      '[__tomg]\nobfuscate = [1]',
    ]) {
      expect(
        () => TomgRegistryDocument.parse(source, source: 'bad.toml'),
        throwsA(isA<TomgDocumentException>()),
      );
    }
  });
}

@Timeout.factor(3)
library;

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:source_gen/source_gen.dart';
import 'package:test/test.dart';
import 'package:tomgen/builder.dart';
import 'package:tomgen/src/tomg_generator.dart';
import 'package:tomg/tomg.dart';

void main() {
  final builder = tomgBuilder(BuilderOptions.empty);

  test('generates a const registry from TOML', () async {
    final result = await testBuilder(
      builder,
      _assets('''
[first]
id = "first"
name = "First"
'''),
      rootPackage: 'tomgen',
      generateFor: const {'tomgen|lib/model.dart'},
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final output = result.readerWriter.testing.readString(
      AssetId('tomgen', 'lib/model.tomg.g.part'),
    );
    expect(output, contains(r'const Map<String, Entry> $Entry'));
    expect(output, contains('"first": Entry(id: "first", name: "First")'));
  });

  test('rejects an unknown TOML field with source and table context', () async {
    final result = await testBuilder(
      builder,
      _assets('''
[first]
id = "first"
name = "First"
naem = "typo"
'''),
      rootPackage: 'tomgen',
      generateFor: const {'tomgen|lib/model.dart'},
      flattenOutput: true,
    );

    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      allOf(contains('config.toml'), contains('first'), contains('naem')),
    );
  });

  test('rejects duplicate registry keys and names both tables', () async {
    final result = await testBuilder(
      builder,
      _assets('''
[first]
id = "same"
name = "First"

[second]
id = "same"
name = "Second"
'''),
      rootPackage: 'tomgen',
      generateFor: const {'tomgen|lib/model.dart'},
      flattenOutput: true,
    );

    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      allOf(
        contains('Duplicate registry key'),
        contains('same'),
        contains('first'),
        contains('second'),
      ),
    );
  });

  group('TOML obfuscation metadata', () {
    test('accepts matching fields in any order and omits metadata', () async {
      for (final fields in <String>['"name", "value"', '"value", "name"']) {
        final result = await testBuilder(
          builder,
          _typedAssets(
            toml:
                '''
[__tomg]
obfuscate = [$fields]

[first]
id = "first"
name = "display plaintext"
value = "private plaintext"
''',
            model: '''
@TomgRegistry('config.toml', key: 'id')
class Entry {
  const Entry({
    required this.id,
    @Obfus() required this.name,
    @Obfus() required this.value,
  });
  final String id;
  @Obfus()
  final String name;
  @Obfus()
  final String value;
}
''',
          ),
          rootPackage: 'tomgen',
          generateFor: const {'tomgen|lib/model.dart'},
          flattenOutput: true,
        );

        expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
        final output = _outputOf(result);
        expect(output, isNot(contains('__tomg')));
        expect(output, isNot(contains('display plaintext')));
        expect(output, isNot(contains('private plaintext')));
        expect(output, contains('class EntryDeobf'));
      }
    });

    test('preserves metadata-free output', () async {
      final result = await testBuilder(
        builder,
        _assets('''
[first]
id = "first"
name = "First"
'''),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      expect(
        _outputOf(result),
        '''// **************************************************************************
// TomgGenerator
// **************************************************************************

const Map<String, Entry> \$Entry = <String, Entry>{
  "first": Entry(id: "first", name: "First"),
};
''',
      );
    });

    for (final fixture
        in <({String name, String toml, String expected, String? hidden})>[
          (
            name: 'non-table reserved value',
            toml: '''
__tomg = "metadata-secret"

[first]
id = "first"
name = "First"
''',
            expected: 'TOML table',
            hidden: 'metadata-secret',
          ),
          (
            name: 'missing obfuscate key',
            toml: '''
[__tomg]

[first]
id = "first"
name = "First"
''',
            expected: 'missing required key "obfuscate"',
            hidden: null,
          ),
          (
            name: 'unknown metadata key',
            toml: '''
[__tomg]
obfuscate = []
future = "metadata-secret"

[first]
id = "first"
name = "First"
''',
            expected: '__tomg.future',
            hidden: 'metadata-secret',
          ),
          (
            name: 'non-array obfuscate value',
            toml: '''
[__tomg]
obfuscate = "metadata-secret"

[first]
id = "first"
name = "First"
''',
            expected: 'array of unique field-name strings',
            hidden: 'metadata-secret',
          ),
          (
            name: 'non-string obfuscate item',
            toml: '''
[__tomg]
obfuscate = [7]

[first]
id = "first"
name = "First"
''',
            expected: '__tomg.obfuscate[0]',
            hidden: null,
          ),
          (
            name: 'duplicate obfuscate item',
            toml: '''
[__tomg]
obfuscate = ["name", "name"]

[first]
id = "first"
name = "First"
''',
            expected: 'Duplicate field "name"',
            hidden: null,
          ),
          (
            name: 'ordinary row using the reserved name',
            toml: '''
[__tomg]
id = "__tomg"
name = "registry-secret"

[first]
id = "first"
name = "First"
''',
            expected: 'Unknown metadata key',
            hidden: 'registry-secret',
          ),
        ]) {
      test('rejects ${fixture.name}', () async {
        final result = await testBuilder(
          builder,
          _assets(fixture.toml),
          rootPackage: 'tomgen',
          generateFor: const {'tomgen|lib/model.dart'},
          flattenOutput: true,
        );

        expect(result.succeeded, isFalse);
        final errors = result.errors.join('\n');
        expect(
          errors,
          allOf(
            contains('config.toml'),
            contains('__tomg'),
            contains(fixture.expected),
          ),
        );
        if (fixture.hidden case final hidden?) {
          expect(errors, isNot(contains(hidden)));
        }
      });
    }

    test('rejects a TOML field missing its Dart annotation', () async {
      final result = await testBuilder(
        builder,
        _assets('''
[__tomg]
obfuscate = ["name"]

[first]
id = "first"
name = "registry-secret"
'''),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        allOf(
          contains('config.toml'),
          contains('Entry'),
          contains('name'),
          contains('@Obfus'),
          isNot(contains('registry-secret')),
        ),
      );
    });

    test('rejects a Dart field missing from TOML metadata', () async {
      final result = await testBuilder(
        builder,
        _assets(
          '''
[__tomg]
obfuscate = []

[first]
id = "first"
name = "registry-secret"
''',
          extraField: '@Obfus() required this.value,',
          extraMember: '@Obfus()\nfinal String value;',
        ),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        allOf(
          contains('config.toml'),
          contains('Entry'),
          contains('value'),
          contains('missing from "__tomg.obfuscate"'),
          isNot(contains('registry-secret')),
        ),
      );
    });

    test('rejects an unknown TOML obfuscation field', () async {
      final result = await testBuilder(
        builder,
        _assets('''
[__tomg]
obfuscate = ["private_value"]

[first]
id = "first"
name = "registry-secret"
'''),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        allOf(
          contains('config.toml'),
          contains('Entry'),
          contains('private_value'),
          contains('unknown field'),
          isNot(contains('registry-secret')),
        ),
      );
    });

    test('retains unsupported obfuscation type validation', () async {
      final result = await testBuilder(
        builder,
        _typedAssets(
          toml: '''
[__tomg]
obfuscate = ["mode"]

[first]
id = "first"
mode = "primary"
''',
          model: '''
enum Mode { primary }

@TomgRegistry('config.toml', key: 'id')
class Entry {
  const Entry({required this.id, @Obfus() required this.mode});
  final String id;
  @Obfus()
  final Mode mode;
}
''',
        ),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        allOf(
          contains('config.toml'),
          contains('Entry.mode'),
          contains('Mode'),
          contains('@Obfus'),
        ),
      );
    });
  });

  test('emits an exactly representable obfuscated double', () async {
    final result = await testBuilder(
      builder,
      _assets(
        '''
[first]
id = "first"
name = "First"
value = -0.0
''',
        extraField: '@Obfus() required this.value,',
        extraMember: '@Obfus()\n  final double value;',
      ),
      rootPackage: 'tomgen',
      generateFor: const {'tomgen|lib/model.dart'},
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final output = result.readerWriter.testing.readString(
      AssetId('tomgen', 'lib/model.tomg.g.part'),
    );
    expect(output, contains('value:'));
    expect(output, isNot(contains('value: -0.0')));
  });

  test('rejects an obfuscated double with non-finite ciphertext', () async {
    final result = await testBuilder(
      builder,
      _assets(
        '''
[first]
id = "first"
name = "First"
value = 1.3189281120125362e-126
''',
        extraField: '@Obfus() required this.value,',
        extraMember: '@Obfus()\n  final double value;',
      ),
      rootPackage: 'tomgen',
      generateFor: const {'tomgen|lib/model.dart'},
      flattenOutput: true,
    );

    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      allOf(contains('first.value'), contains('not a finite Dart constant')),
    );
  });

  group('environment substitution', () {
    test(
      'resolves values, defaults, empty values, equals, and escaping',
      () async {
        final result = await testBuilder(
          _builderWithEnvironment({
            'NAME': 'From environment',
            'LABEL': '',
            'SECOND': 'must not be expanded',
          }),
          _assets(
            r'''
[first]
id = "first"
name = "$NAME"
label = "$LABEL=fallback"
token = "$TOKEN=a=b=c"
escaped = "$$API_URL"
embedded = "cost-$USD"
nested = "$PRIMARY=$SECOND"
''',
            extraField: '''
required this.label,
required this.token,
required this.escaped,
required this.embedded,
required this.nested,''',
            extraMember: '''
final String label;
final String token;
final String escaped;
final String embedded;
final String nested;''',
          ),
          rootPackage: 'tomgen',
          generateFor: const {'tomgen|lib/model.dart'},
          flattenOutput: true,
        );

        expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
        final output = _outputOf(result);
        expect(output, contains('name: "From environment"'));
        expect(output, contains('label: ""'));
        expect(output, contains('token: "a=b=c"'));
        expect(output, contains(r'escaped: "\$API_URL"'));
        expect(output, contains(r'embedded: "cost-\$USD"'));
        expect(output, contains(r'nested: "\$SECOND"'));
      },
    );

    test('rejects malformed references with field context', () async {
      final result = await testBuilder(
        _builderWithEnvironment(const {}),
        _assets(r'''
[first]
id = "first"
name = "$9INVALID"
'''),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        allOf(
          contains('Invalid environment reference'),
          contains('config.toml'),
          contains('first.name'),
        ),
      );
    });

    test('reports a missing required variable without a value', () async {
      final result = await testBuilder(
        _builderWithEnvironment(const {}),
        _assets(r'''
[first]
id = "first"
name = "$MISSING_SECRET"
'''),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        allOf(
          contains('MISSING_SECRET'),
          contains('config.toml'),
          contains('first.name'),
          isNot(contains('secret-value')),
        ),
      );
    });

    test('converts string, int, double, and bool environment values', () async {
      final result = await testBuilder(
        _builderWithEnvironment({
          'NAME': 'typed',
          'COUNT': '42',
          'RATIO': '1.25',
          'ENABLED': 'false',
        }),
        _assets(
          r'''
[first]
id = "first"
name = "$NAME"
count = "$COUNT"
ratio = "$RATIO"
enabled = "$ENABLED"
''',
          extraField: '''
required this.count,
required this.ratio,
required this.enabled,''',
          extraMember: '''
final int count;
final double ratio;
final bool enabled;''',
        ),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final output = _outputOf(result);
      expect(output, contains('name: "typed"'));
      expect(output, contains('count: 42'));
      expect(output, contains('ratio: 1.25'));
      expect(output, contains('enabled: false'));
    });

    test(
      'reports conversion context without leaking the resolved value',
      () async {
        const secretValue = 'private-not-an-int';
        final result = await testBuilder(
          _builderWithEnvironment(const {'COUNT': secretValue}),
          _assets(
            r'''
[first]
id = "first"
name = "First"
count = "$COUNT"
''',
            extraField: 'required this.count,',
            extraMember: 'final int count;',
          ),
          rootPackage: 'tomgen',
          generateFor: const {'tomgen|lib/model.dart'},
          flattenOutput: true,
        );

        expect(result.succeeded, isFalse);
        expect(
          result.errors.join('\n'),
          allOf(
            contains('COUNT'),
            contains('int'),
            contains('config.toml'),
            contains('first.count'),
            isNot(contains(secretValue)),
          ),
        );
      },
    );

    test(
      'uses resolved registry keys and detects resolved collisions',
      () async {
        final success = await testBuilder(
          _builderWithEnvironment(const {'ENTRY_ID': 'from-env'}),
          _assets(r'''
[first]
id = "$ENTRY_ID"
name = "First"
'''),
          rootPackage: 'tomgen',
          generateFor: const {'tomgen|lib/model.dart'},
          flattenOutput: true,
        );
        expect(success.succeeded, isTrue, reason: success.errors.join('\n'));
        expect(
          _outputOf(success),
          contains('"from-env": Entry(id: "from-env"'),
        );

        final collision = await testBuilder(
          _builderWithEnvironment(const {
            'FIRST_ID': 'same',
            'SECOND_ID': 'same',
          }),
          _assets(r'''
[first]
id = "$FIRST_ID"
name = "First"

[second]
id = "$SECOND_ID"
name = "Second"
'''),
          rootPackage: 'tomgen',
          generateFor: const {'tomgen|lib/model.dart'},
          flattenOutput: true,
        );
        expect(collision.succeeded, isFalse);
        expect(
          collision.errors.join('\n'),
          allOf(
            contains('Duplicate registry key'),
            contains('first'),
            contains('second'),
          ),
        );
      },
    );

    test('obfuscates the resolved environment value', () async {
      const plaintext = 'environment secret';
      final result = await testBuilder(
        _builderWithEnvironment(const {'SECRET_VALUE': plaintext}),
        _assets(
          r'''
[first]
id = "first"
name = "First"
value = "$SECRET_VALUE"
''',
          extraField: '@Obfus() required this.value,',
          extraMember: '@Obfus()\nfinal String value;',
        ),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final output = _outputOf(result);
      expect(output, contains(TomgCodec.encodeString(plaintext)));
      expect(output, isNot(contains(plaintext)));
      expect(output, isNot(contains(r'$SECRET_VALUE')));
    });
  });

  group('nullable, enum, and list values', () {
    test(
      'renders present nullable values and omits optional nullable fields',
      () async {
        final result = await testBuilder(
          builder,
          _typedAssets(
            toml: '''
[first]
id = "first"
count = 7
''',
            model: '''
@TomgRegistry('config.toml', key: 'id')
class Entry {
  const Entry({required this.id, required this.count, this.note});
  final String id;
  final int? count;
  final String? note;
}
''',
          ),
          rootPackage: 'tomgen',
          generateFor: const {'tomgen|lib/model.dart'},
          flattenOutput: true,
        );

        expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
        final output = _outputOf(result);
        expect(output, contains('count: 7'));
        expect(output, isNot(contains('note:')));
      },
    );

    test('keeps a nullable required parameter required', () async {
      final result = await testBuilder(
        builder,
        _typedAssets(
          toml: '''
[first]
id = "first"
''',
          model: '''
@TomgRegistry('config.toml', key: 'id')
class Entry {
  const Entry({required this.id, required this.note});
  final String id;
  final String? note;
}
''',
        ),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        allOf(contains('config.toml'), contains('first'), contains('note')),
      );
    });

    test('renders enum values, enum lists, and enum registry keys', () async {
      final result = await testBuilder(
        builder,
        _typedAssets(
          toml: '''
[primary]
mode = "production"
allowed = ["development", "production"]
''',
          model: '''
enum Mode { development, production }

@TomgRegistry('config.toml', key: 'mode')
class Entry {
  const Entry({required this.mode, required this.allowed});
  final Mode mode;
  final List<Mode> allowed;
}
''',
        ),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final output = _outputOf(result);
      expect(output, contains(r'const Map<Mode, Entry> $Entry'));
      expect(output, contains('Mode.production: Entry('));
      expect(output, contains('mode: Mode.production'));
      expect(
        output,
        contains('allowed: const <Mode>[Mode.development, Mode.production]'),
      );
    });

    test('renders a prefixed imported enum reference', () async {
      final result = await testBuilder(
        builder,
        _typedAssets(
          toml: '''
[first]
id = "first"
kind = "primary"
''',
          imports: "import 'package:tomgen/types.dart' as kinds;",
          model: '''
@TomgRegistry('config.toml', key: 'id')
class Entry {
  const Entry({required this.id, required this.kind});
  final String id;
  final kinds.Kind kind;
}
''',
          extraAssets: const {
            'tomgen|lib/types.dart': 'enum Kind { primary, secondary }',
          },
        ),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      expect(_outputOf(result), contains('kind: kinds.Kind.primary'));
    });

    test('reports invalid enum values and allowed members', () async {
      final result = await testBuilder(
        builder,
        _typedAssets(
          toml: '''
[first]
id = "first"
mode = "Production"
''',
          model: '''
enum Mode { development, production }
@TomgRegistry('config.toml', key: 'id')
class Entry {
  const Entry({required this.id, required this.mode});
  final String id;
  final Mode mode;
}
''',
        ),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        allOf(
          contains('config.toml'),
          contains('first.mode'),
          contains('Production'),
          contains('Mode'),
          contains('development, production'),
        ),
      );
    });

    test('detects duplicate enum registry keys', () async {
      final result = await testBuilder(
        builder,
        _typedAssets(
          toml: '''
[first]
mode = "production"

[second]
mode = "production"
''',
          model: '''
enum Mode { development, production }
@TomgRegistry('config.toml', key: 'mode')
class Entry {
  const Entry({required this.mode});
  final Mode mode;
}
''',
        ),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        allOf(
          contains('Duplicate registry key'),
          contains('Mode.production'),
          contains('first'),
          contains('second'),
        ),
      );
    });

    test(
      'renders every scalar list type and resolves each environment item',
      () async {
        final result = await testBuilder(
          _builderWithEnvironment(const {
            'LABEL': 'from-env',
            'COUNT': '2',
            'RATIO': '2.5',
            'FLAG': 'false',
          }),
          _typedAssets(
            toml: r'''
[first]
id = "first"
labels = ["literal", "$LABEL"]
counts = [1, "$COUNT"]
ratios = [1.0, "$RATIO"]
flags = [true, "$FLAG"]
''',
            model: '''
@TomgRegistry('config.toml', key: 'id')
class Entry {
  const Entry({
    required this.id,
    required this.labels,
    required this.counts,
    required this.ratios,
    required this.flags,
  });
  final String id;
  final List<String> labels;
  final List<int> counts;
  final List<double> ratios;
  final List<bool> flags;
}
''',
          ),
          rootPackage: 'tomgen',
          generateFor: const {'tomgen|lib/model.dart'},
          flattenOutput: true,
        );

        expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
        final output = _outputOf(result);
        expect(
          output,
          contains('labels: const <String>["literal", "from-env"]'),
        );
        expect(output, contains('counts: const <int>[1, 2]'));
        expect(output, contains('ratios: const <double>[1.0, 2.5]'));
        expect(output, contains('flags: const <bool>[true, false]'));
      },
    );

    test(
      'reports an indexed list conversion without leaking environment data',
      () async {
        const secretValue = 'private-not-an-int';
        final result = await testBuilder(
          _builderWithEnvironment(const {'COUNT': secretValue}),
          _typedAssets(
            toml: r'''
[first]
id = "first"
counts = [1, "$COUNT"]
''',
            model: '''
@TomgRegistry('config.toml', key: 'id')
class Entry {
  const Entry({required this.id, required this.counts});
  final String id;
  final List<int> counts;
}
''',
          ),
          rootPackage: 'tomgen',
          generateFor: const {'tomgen|lib/model.dart'},
          flattenOutput: true,
        );

        expect(result.succeeded, isFalse);
        expect(
          result.errors.join('\n'),
          allOf(
            contains('COUNT'),
            contains('config.toml'),
            contains('first.counts[1]'),
            isNot(contains(secretValue)),
          ),
        );
      },
    );
  });

  group('nested const models', () {
    test('renders nested objects and typed model lists', () async {
      final result = await testBuilder(
        builder,
        _typedAssets(
          toml: '''
[first]
id = "first"
database = { host = "db.example", tls = { enabled = true } }
replicas = [{ host = "one.example", priority = 1 }, { host = "two.example" }]
[second]
id = "second"
replicas = []
''',
          model: '''
class Tls {
  const Tls({required this.enabled});
  final bool enabled;
}

class Database {
  const Database({required this.host, required this.tls, this.port = 5432});
  final String host;
  final Tls tls;
  final int port;
}

class Replica {
  const Replica({required this.host, this.priority});
  final String host;
  final int? priority;
}

@TomgRegistry('config.toml', key: 'id')
class Entry {
  const Entry({required this.id, this.database, required this.replicas});
  final String id;
  final Database? database;
  final List<Replica> replicas;
}
''',
        ),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final output = _outputOf(result);
      expect(
        output,
        contains(
          'database: Database(host: "db.example", tls: Tls(enabled: true))',
        ),
      );
      expect(output, contains('const <Replica>['));
      expect(output, contains('Replica(host: "one.example", priority: 1)'));
      expect(output, contains('Replica(host: "two.example")'));
      expect(output, contains('"second": Entry('));
      expect(output, contains('replicas: const <Replica>[]'));
    });

    test('renders prefixed imported nested model references', () async {
      final result = await testBuilder(
        builder,
        _typedAssets(
          toml: '''
[first]
id = "first"
database = { host = "db.example" }
''',
          imports: "import 'models.dart' as cfg;",
          extraAssets: const <String, String>{
            'tomgen|lib/models.dart': '''
class Database {
  const Database({required this.host});
  final String host;
}
''',
          },
          model: '''
@TomgRegistry('config.toml', key: 'id')
class Entry {
  const Entry({required this.id, required this.database});
  final String id;
  final cfg.Database database;
}
''',
        ),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      expect(
        _outputOf(result),
        contains('database: cfg.Database(host: "db.example")'),
      );
    });

    test('renders an unprefixed imported nested model reference', () async {
      final result = await testBuilder(
        builder,
        _typedAssets(
          toml: '[first]\nid = "first"\nchild = { value = "nested" }',
          imports: "import 'models.dart';",
          extraAssets: const <String, String>{
            'tomgen|lib/models.dart': '''
class Child {
  const Child({required this.value});
  final String value;
}
''',
          },
          model: '''
@TomgRegistry('config.toml', key: 'id')
class Entry {
  const Entry({required this.id, required this.child});
  final String id;
  final Child child;
}
''',
        ),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );

      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      expect(_outputOf(result), contains('child: Child(value: "nested")'));
    });

    test('reports indexed nested unknown and missing fields', () async {
      for (final fixture in <({String value, String expected})>[
        (
          value: '{ host = "one", unexpected = true }',
          expected: 'unknown field "unexpected"',
        ),
        (value: '{ priority = 1 }', expected: 'missing required field "host"'),
      ]) {
        final result = await testBuilder(
          builder,
          _typedAssets(
            toml:
                '''
[first]
id = "first"
replicas = [${fixture.value}]
''',
            model: '''
class Replica {
  const Replica({required this.host, this.priority});
  final String host;
  final int? priority;
}

@TomgRegistry('config.toml', key: 'id')
class Entry {
  const Entry({required this.id, required this.replicas});
  final String id;
  final List<Replica> replicas;
}
''',
          ),
          rootPackage: 'tomgen',
          generateFor: const {'tomgen|lib/model.dart'},
          flattenOutput: true,
        );

        expect(result.succeeded, isFalse);
        expect(
          result.errors.join('\n'),
          allOf(contains('first.replicas[0]'), contains(fixture.expected)),
        );
      }
    });

    test('rejects cycles and nested obfuscation before rendering', () async {
      final cycle = await testBuilder(
        builder,
        _typedAssets(
          toml: '[first]\nid = "first"\na = { b = { a = {} } }',
          model: '''
class A {
  const A({required this.b});
  final B b;
}
class B {
  const B({required this.a});
  final A a;
}
@TomgRegistry('config.toml', key: 'id')
class Entry {
  const Entry({required this.id, required this.a});
  final String id;
  final A a;
}
''',
        ),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );
      expect(cycle.succeeded, isFalse);
      expect(cycle.errors.join('\n'), contains('A -> B -> A'));

      final obfuscated = await testBuilder(
        builder,
        _typedAssets(
          toml: '[first]\nid = "first"\nchild = { secret = "value" }',
          model: '''
class Child {
  const Child({@Obfus() required this.secret});
  @Obfus()
  final String secret;
}
@TomgRegistry('config.toml', key: 'id')
class Entry {
  const Entry({required this.id, required this.child});
  final String id;
  final Child child;
}
''',
        ),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );
      expect(obfuscated.succeeded, isFalse);
      expect(
        obfuscated.errors.join('\n'),
        allOf(contains('@Obfus'), contains('nested model'), contains('secret')),
      );
    });

    test('rejects unsupported nested model declarations', () async {
      for (final fixture
          in <({String declaration, String type, String expected})>[
            (
              declaration: '''
class Child {
  Child({required this.value});
  final String value;
}
''',
              type: 'Child',
              expected: 'const unnamed constructor',
            ),
            (
              declaration: '''
class Child {
  const Child(this.value);
  final String value;
}
''',
              type: 'Child',
              expected: 'only named constructor parameters',
            ),
            (
              declaration: '''
class Child<T> {
  const Child({required this.value});
  final T value;
}
''',
              type: 'Child<String>',
              expected: 'non-generic',
            ),
            (
              declaration: '''
abstract class Child {
  const Child({required this.value});
  final String value;
}
''',
              type: 'Child',
              expected: 'concrete constructable class',
            ),
            (
              declaration: '''
class Child {
  const factory Child({required String value}) = ChildImpl;
}
class ChildImpl implements Child {
  const ChildImpl({required this.value});
  final String value;
}
''',
              type: 'Child',
              expected: 'non-factory const unnamed constructor',
            ),
          ]) {
        final result = await testBuilder(
          builder,
          _typedAssets(
            toml: '[first]\nid = "first"\nchild = { value = "nested" }',
            model:
                '''
${fixture.declaration}
@TomgRegistry('config.toml', key: 'id')
class Entry {
  const Entry({required this.id, required this.child});
  final String id;
  final ${fixture.type} child;
}
''',
          ),
          rootPackage: 'tomgen',
          generateFor: const {'tomgen|lib/model.dart'},
          flattenOutput: true,
        );

        expect(result.succeeded, isFalse);
        expect(
          result.errors.join('\n'),
          allOf(contains('Entry.child'), contains(fixture.expected)),
        );
      }
    });

    test('rejects object-valued registry keys', () async {
      final result = await testBuilder(
        builder,
        _typedAssets(
          toml: '[first]\nid = { value = "first" }',
          model: '''
class Identifier {
  const Identifier({required this.value});
  final String value;
}
@TomgRegistry('config.toml', key: 'id')
class Entry {
  const Entry({required this.id});
  final Identifier id;
}
''',
        ),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        allOf(contains('id'), contains('structured registry keys')),
      );
    });
  });

  group('unsupported collection and obfuscation boundaries', () {
    test('does not treat one environment string as a whole list', () async {
      final result = await testBuilder(
        _builderWithEnvironment(const {'LABELS': 'one,two'}),
        _typedAssets(
          toml: r'''
[first]
id = "first"
labels = "$LABELS"
''',
          model: '''
@TomgRegistry('config.toml', key: 'id')
class Entry {
  const Entry({required this.id, required this.labels});
  final String id;
  final List<String> labels;
}
''',
        ),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        allOf(
          contains('config.toml'),
          contains('first.labels'),
          contains('whole list'),
        ),
      );
    });

    test('rejects nested lists with the declared field path', () async {
      final result = await testBuilder(
        builder,
        _typedAssets(
          toml: '''
[first]
id = "first"
matrix = [["value"]]
''',
          model: '''
@TomgRegistry('config.toml', key: 'id')
class Entry {
  const Entry({required this.id, required this.matrix});
  final String id;
  final List<List<String>> matrix;
}
''',
        ),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        allOf(contains('config.toml'), contains('Entry.matrix[]')),
      );
    });

    test('rejects a collection registry key', () async {
      final result = await testBuilder(
        builder,
        _typedAssets(
          toml: '''
[first]
ids = ["first"]
''',
          model: '''
@TomgRegistry('config.toml', key: 'ids')
class Entry {
  const Entry({required this.ids});
  final List<String> ids;
}
''',
        ),
        rootPackage: 'tomgen',
        generateFor: const {'tomgen|lib/model.dart'},
        flattenOutput: true,
      );

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        allOf(contains('config.toml'), contains('ids'), contains('registry')),
      );
    });

    for (final fixture in <({String type, String toml})>[
      (type: 'Mode', toml: 'mode = "primary"'),
      (type: 'List<String>', toml: 'mode = ["primary"]'),
    ]) {
      test('rejects @Obfus on ${fixture.type}', () async {
        final enumDeclaration = fixture.type == 'Mode'
            ? 'enum Mode { primary }'
            : '';
        final result = await testBuilder(
          builder,
          _typedAssets(
            toml:
                '''
[first]
id = "first"
${fixture.toml}
''',
            model:
                '''
$enumDeclaration
@TomgRegistry('config.toml', key: 'id')
class Entry {
  const Entry({required this.id, @Obfus() required this.mode});
  final String id;
  @Obfus()
  final ${fixture.type} mode;
}
''',
          ),
          rootPackage: 'tomgen',
          generateFor: const {'tomgen|lib/model.dart'},
          flattenOutput: true,
        );

        expect(result.succeeded, isFalse);
        expect(
          result.errors.join('\n'),
          allOf(
            contains('@Obfus'),
            contains('config.toml'),
            contains('Entry.mode'),
            contains(fixture.type),
          ),
        );
      });
    }
  });
}

Builder _builderWithEnvironment(Map<String, String> environment) =>
    SharedPartBuilder([TomgGenerator(environment: environment)], 'tomg');

String _outputOf(TestBuilderResult result) => result.readerWriter.testing
    .readString(AssetId('tomgen', 'lib/model.tomg.g.part'));

Map<String, String> _typedAssets({
  required String toml,
  required String model,
  String imports = '',
  Map<String, String> extraAssets = const {},
}) => <String, String>{
  'tomg|lib/tomg.dart': '''
class TomgRegistry {
  const TomgRegistry(this.source, {required this.key});
  final String source;
  final String key;
}

class Obfus {
  const Obfus();
}
''',
  'tomgen|lib/model.dart':
      '''
import 'package:tomg/tomg.dart';
$imports

part 'model.g.dart';

$model
''',
  'tomgen|lib/config.toml': toml,
  ...extraAssets,
};

Map<String, String> _assets(
  String toml, {
  String extraField = '',
  String extraMember = '',
}) => <String, String>{
  'tomg|lib/tomg.dart': '''
class TomgRegistry {
  const TomgRegistry(this.source, {required this.key});
  final String source;
  final String key;
}

class Obfus {
  const Obfus();
}
''',
  'tomgen|lib/model.dart':
      '''
import 'package:tomg/tomg.dart';

part 'model.g.dart';

@TomgRegistry('config.toml', key: 'id')
class Entry {
  const Entry({required this.id, required this.name, $extraField});

  final String id;
  final String name;
  $extraMember
}
''',
  'tomgen|lib/config.toml': toml,
};

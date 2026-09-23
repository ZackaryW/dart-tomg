import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tomgen/src/cli/config.dart';
import 'package:tomgen/src/cli/emitter.dart';
import 'package:tomgen/src/cli/errors.dart';
import 'package:tomgen/src/cli/project.dart';
import 'package:tomgen/src/cli/schema.dart';
import 'package:tomgen/src/registry_document.dart';

import 'test_support.dart';

void main() {
  late TestPackage package;

  setUp(() => package = TestPackage.create(name: 'schema_example'));
  tearDown(() => package.dispose());

  test('infers scalars, numeric widening, optional fields, and defaults', () {
    final schema = _schema(
      package,
      toml: '''
[one]
id = "one"
score = 1
note = "hello"
[two]
id = "two"
score = 2.5
''',
      defaults: 'enabled = true',
    );
    expect(schema.keyField.name, 'id');
    expect(_field(schema, 'score').type.dartType, 'double');
    expect(_field(schema, 'score').required, isTrue);
    expect(_field(schema, 'note').dartType, 'String?');
    expect(_field(schema, 'enabled').dartType, 'bool');
    expect(_field(schema, 'enabled').defaultValue, isTrue);
  });

  test('infers lists across rows and widens numeric items', () {
    final schema = _schema(
      package,
      toml: '''
[one]
id = "one"
values = [1, 2]
[two]
id = "two"
values = [2.5]
''',
    );
    expect(_field(schema, 'values').type.dartType, 'List<double>');
  });

  test('applies scalar and list enums, including environment placeholders', () {
    final schema = _schema(
      package,
      toml: '''
[one]
id = "one"
status = "live"
transports = []
[two]
id = "two"
status = "\$STATUS=disabled"
transports = ["https", "\$TRANSPORT=https"]
''',
      enums: '''
[targets.items.enums.status]
name = "Status"
values = ["live", "disabled"]
[targets.items.enums.transports]
name = "Transport"
values = ["https", "grpc"]
''',
    );
    expect(_field(schema, 'status').type.dartType, 'Status');
    expect(_field(schema, 'transports').type.dartType, 'List<Transport>');
    expect(schema.enumDeclarations.map((value) => value.name), <String>[
      'Status',
      'Transport',
    ]);
  });

  test('rejects conflicting reuse of an enum name', () {
    expect(
      () => _schema(
        package,
        toml: '''
[one]
id = "one"
status = "live"
mode = "fast"
''',
        enums: '''
[targets.items.enums.status]
name = "State"
values = ["live"]
[targets.items.enums.mode]
name = "State"
values = ["fast"]
''',
      ),
      throwsA(
        isA<TomgenException>().having(
          (error) => error.message,
          'message',
          contains('conflicting member lists'),
        ),
      ),
    );
  });

  test('reports conflicting and unsupported shapes with field context', () {
    for (final toml in <String>[
      '[one]\nid = "one"\nvalue = "x"\n[two]\nid = "two"\nvalue = 1',
      '[one]\nid = "one"\nvalue = [1]\n[two]\nid = "two"\nvalue = 1',
      '[one]\nid = "one"\nvalue = [[1]]',
      '[one]\nid = "one"\nvalue = []\n[two]\nid = "two"\nvalue = []',
      '[one]\nid = "one"\nvalue = 1979-05-27T07:32:00Z',
    ]) {
      expect(
        () => _schema(package, toml: toml),
        throwsA(
          isA<TomgenException>().having(
            (error) => error.message,
            'message',
            contains('value'),
          ),
        ),
        reason: toml,
      );
    }
  });

  test(
    'rejects empty registries, unknown keys, enums, and obfuscation targets',
    () {
      expect(
        () => _schema(package, toml: '[__tomg]\nobfuscate = []'),
        throwsA(isA<TomgenException>()),
      );
      expect(
        () => _schema(package, toml: '[one]\nother = "x"'),
        throwsA(isA<TomgenException>()),
      );
      expect(
        () => _schema(
          package,
          toml: '[one]\nid = "one"\nstatus = "unknown"',
          enums: '''
[targets.items.enums.status]
name = "Status"
values = ["live"]
''',
        ),
        throwsA(isA<TomgenException>()),
      );
      expect(
        () => _schema(
          package,
          toml: '''
[__tomg]
obfuscate = ["values"]
[one]
id = "one"
values = [1]
''',
        ),
        throwsA(isA<TomgenException>()),
      );
    },
  );

  test('emits the endpoint golden with the full obfuscation contract', () {
    final schema = _schema(
      package,
      model: 'ApiEndpoint',
      toml: '''
[__tomg]
obfuscate = ["url"]
[one]
id = "one"
name = "One"
url = "https://one.example"
[two]
id = "two"
name = "Two"
url = "https://two.example"
enabled = false
''',
      defaults: 'enabled = true',
    );
    final actual = TomgenEmitter().emit(schema, packageName: 'schema_example');
    final golden = _golden('api_endpoint.golden').readAsStringSync();
    expect(actual, golden);
    expect(actual, isNot(contains('https://one.example')));
    expect(actual, contains('implements Obfuscated<ApiEndpointDeobf>'));
  });

  test('emits the service plan enum and list golden', () {
    final schema = _schema(
      package,
      model: 'ServicePlan',
      toml: '''
[starter]
tier = "starter"
regions = ["us-east"]
transports = ["https"]
[enterprise]
tier = "enterprise"
regions = ["us-east", "eu-west"]
transports = ["https", "grpc"]
description = "Multi-region"
''',
      key: 'tier',
      enums: '''
[targets.items.enums.tier]
name = "PlanTier"
values = ["starter", "enterprise"]
[targets.items.enums.transports]
name = "Transport"
values = ["https", "grpc"]
''',
    );
    final actual = TomgenEmitter().emit(schema, packageName: 'schema_example');
    final golden = _golden('service_plan.golden').readAsStringSync();
    expect(actual, golden);
  });

  test('infers nested objects and model lists across every occurrence', () {
    final schema = _schema(
      package,
      model: 'Service',
      toml: '''
[one]
id = "one"
database = { host = "db-one", tls = { enabled = true } }
replicas = [{ host = "replica-one", transport = "https" }]
[two]
id = "two"
database = { host = "db-two" }
replicas = [{ host = "replica-two", transport = "grpc", priority = 1 }, { host = "replica-three", transport = "https" }]
''',
      defaults: '"database.port" = 5432',
      enums: '''
[targets.items.enums."replicas.transport"]
name = "Transport"
values = ["https", "grpc"]
''',
    );

    expect(schema.models.map((model) => model.name), <String>[
      'ServiceDatabaseTls',
      'ServiceDatabase',
      'ServiceReplicasItem',
      'Service',
    ]);
    expect(_field(schema, 'database').type.dartType, 'ServiceDatabase');
    expect(
      _field(schema, 'replicas').type.dartType,
      'List<ServiceReplicasItem>',
    );
    final database = schema.models.singleWhere(
      (model) => model.name == 'ServiceDatabase',
    );
    expect(_modelField(database, 'tls').dartType, 'ServiceDatabaseTls?');
    expect(_modelField(database, 'port').dartType, 'int');
    expect(_modelField(database, 'port').defaultValue, 5432);
    final replica = schema.models.singleWhere(
      (model) => model.name == 'ServiceReplicasItem',
    );
    expect(_modelField(replica, 'transport').dartType, 'Transport');
    expect(_modelField(replica, 'priority').dartType, 'int?');

    final output = TomgenEmitter().emit(schema, packageName: 'schema_example');
    expect(output, contains('class ServiceDatabaseTls'));
    expect(output, contains('class ServiceDatabase'));
    expect(output, contains('class ServiceReplicasItem'));
    expect(output, contains('final List<ServiceReplicasItem> replicas;'));
  });

  test('rejects conflicting structured shapes with the full field path', () {
    expect(
      () => _schema(
        package,
        toml: '''
[one]
id = "one"
database = { port = 5432 }
[two]
id = "two"
database = { port = "5432" }
''',
      ),
      throwsA(
        isA<TomgenException>().having(
          (error) => error.message,
          'message',
          allOf(contains('database.port'), contains('two')),
        ),
      ),
    );
  });

  test('rejects object keys, object obfuscation, and all-empty lists', () {
    for (final fixture in <({String toml, String expected})>[
      (toml: '[one]\nid = { value = "one" }', expected: 'cannot be an object'),
      (
        toml:
            '[__tomg]\nobfuscate = ["database"]\n[one]\nid = "one"\ndatabase = { port = 5432 }',
        expected: 'unsupported type ItemDatabase',
      ),
      (toml: '[one]\nid = "one"\nreplicas = []', expected: 'only empty lists'),
    ]) {
      expect(
        () => _schema(package, toml: fixture.toml),
        throwsA(
          isA<TomgenException>().having(
            (error) => error.message,
            'message',
            contains(fixture.expected),
          ),
        ),
      );
    }
  });

  test('keeps inferred graph and output stable across row order', () {
    final first = _schema(
      package,
      model: 'Service',
      toml: '''
[one]
id = "one"
database = { host = "one", port = 1 }
[two]
id = "two"
database = { host = "two", port = 2.5 }
''',
    );
    final firstOutput = TomgenEmitter().emit(
      first,
      packageName: 'schema_example',
    );
    final second = _schema(
      package,
      model: 'Service',
      toml: '''
[two]
id = "two"
database = { port = 2.5, host = "two" }
[one]
id = "one"
database = { port = 1, host = "one" }
''',
    );
    final secondOutput = TomgenEmitter().emit(
      second,
      packageName: 'schema_example',
    );

    expect(secondOutput, firstOutput);
  });

  test('reports both paths when inferred model names collide', () {
    expect(
      () => _schema(
        package,
        toml: '''
[one]
id = "one"
foo_bar = { value = "one" }
fooBar = { value = "two" }
''',
      ),
      throwsA(
        isA<TomgenException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('foo_bar'),
            contains('fooBar'),
            contains('ItemFooBar'),
          ),
        ),
      ),
    );
  });

  test('rejects dotted hints that cannot reach an inferred leaf', () {
    for (final fixture in <({String defaults, String enums})>[
      (defaults: '"missing.value" = 1', enums: ''),
      (
        defaults: '',
        enums: '''
[targets.items.enums.database]
name = "DatabaseKind"
values = ["primary"]
''',
      ),
    ]) {
      expect(
        () => _schema(
          package,
          toml: '[one]\nid = "one"\ndatabase = { host = "db" }',
          defaults: fixture.defaults,
          enums: fixture.enums,
        ),
        throwsA(isA<TomgenException>()),
      );
    }
  });
}

TomgenSchema _schema(
  TestPackage package, {
  required String toml,
  String model = 'Item',
  String key = 'id',
  String defaults = '',
  String enums = '',
}) {
  package.write('config/items.toml', toml);
  package.write('g.toml', '''
version = 1
output = "lib/generated"
[targets.items]
source = "config/items.toml"
model = "$model"
key = "$key"
${defaults.isEmpty ? '' : '[targets.items.defaults]\n$defaults'}
$enums
''');
  final config = TomgenConfig.load(TomgenProject.discover(package.root));
  return TomgenSchema.infer(
    config.targets.single,
    TomgRegistryDocument.parse(toml, source: 'config/items.toml'),
  );
}

TomgenField _field(TomgenSchema schema, String name) =>
    schema.fields.singleWhere((field) => field.name == name);

TomgenField _modelField(TomgenModel model, String name) =>
    model.fields.singleWhere((field) => field.name == name);

File _golden(String name) {
  final packageLocal = File(p.join('test', 'goldens', name));
  if (packageLocal.existsSync()) return packageLocal;
  return File(p.join('tomgen', 'test', 'goldens', name));
}

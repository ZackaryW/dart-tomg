# dart-tomg

Generate typed, compile-time-constant Dart registries from TOML.

`dart-tomg` is useful when an application has a small registry of endpoints,
feature definitions, plans, regions, or similar records that is easier to edit
as TOML but should ship as typed Dart objects without runtime file I/O.

## TOML-first workflow

Add `tomg` as a dependency and `tomgen` plus `build_runner` as development
dependencies. At the package root, declare generated models in `g.toml`:

```toml
version = 1
output = "lib/generated"

[targets.api_endpoints]
source = "config/api_endpoints.toml"
model = "ApiEndpoint"
key = "id"

[targets.api_endpoints.defaults]
visible = true
enabled = true

[targets.service_plans]
source = "config/service_plans.toml"
model = "ServicePlan"
key = "tier"

[targets.service_plans.enums.tier]
name = "PlanTier"
values = ["starter", "enterprise"]
```

Run both generation phases with one command:

```sh
dart run tomgen build
```

Phase one infers model shapes and writes annotated Dart libraries beneath the
configured `lib/` directory. Phase two runs build_runner to produce typed const
registries and decoded companions. Use `dart run tomgen generate` for phase one
only and `dart run tomgen clean` to remove unchanged phase-one files owned by
tomgen. Arguments after `--` on `tomgen build` are forwarded to build_runner.

Inference examines every row. Fields present everywhere are required; fields
omitted by a row become nullable unless `g.toml` supplies a compatible default.
Integers and doubles widen to `double`, and homogeneous flat arrays become
`List<T>`. String data remains `String` unless an explicit enum declaration
supplies its Dart name and allowed members. Nested tables and inline tables
become nested const model classes, while arrays of tables become
`List<Model>`. tomgen derives those classes afresh from the current TOML on
every run; it neither requires nor creates a schema lock file.

Nested names come from the configured root model and complete field path. For
example, `Service.database.tls` becomes `ServiceDatabaseTls`, and a
`Service.replicas` array of tables uses `ServiceReplicasItem`. Defaults and enum
declarations can target nested leaves with quoted dotted keys:

```toml
[targets.services.defaults]
"database.port" = 5432

[targets.services.enums."replicas.transport"]
name = "Transport"
values = ["https", "grpc"]
```

A structural TOML edit changes the generated Dart API on the next run. Commit
and review the generated Dart diff when consumers need an API review boundary.

TOML under a root directory such as `config/` remains outside `lib/` and is not
a runtime asset. Include that directory in the package build graph:

```yaml
targets:
  $default:
    sources:
      - $package$
      - lib/**
      - bin/**
      - test/**
      - config/**
```

tomgen records phase-one ownership in `.dart_tool/tomgen/manifest.json` and
uses content hashes, generated notices, atomic replacement, and stale-file
cleanup. It will not overwrite handwritten or edited files. An identical
checked-in generated model can be adopted without being rewritten on a fresh
clone.

## Model-first workflow

The annotation-driven workflow remains available when you want to write the
model API yourself:

```toml
[__tomg]
obfuscate = ["url"]

[us-east]
id = "us-east"
name = "US East"
url = "https://api.us-east.example.com"
```

```dart
@TomgRegistry('api_endpoint.toml', key: 'id')
class ApiEndpoint implements Obfuscated<ApiEndpointDeobf> {
  const ApiEndpoint({
    required this.id,
    required this.name,
    @Obfus() required this.url,
  });

  final String id;
  final String name;

  @Obfus()
  final String url;

  @override
  ApiEndpointDeobf get deobf => ApiEndpointDeobf(this);
}

const endpoints = $ApiEndpoint;
```

After `dart run build_runner build`, `endpoints` is a `const
Map<String, ApiEndpoint>`. Marked fields are stored as deterministic ciphertext
and decoded at runtime through `endpoint.deobf.url`.

The optional `[__tomg]` table makes the same obfuscation policy visible beside
the TOML data. When present, `obfuscate` must list exactly the fields carrying
`@Obfus` in Dart. A missing, extra, duplicate, unknown, or unsupported field
fails generation. TOML metadata confirms the Dart contract; it does not enable
obfuscation by itself. Files without this table keep the Dart-only behavior.

`__tomg` is reserved for generator metadata and cannot also be a registry entry.

## Packages

- [`tomg`](tomg/) contains the annotations, runtime codec, `.deobf`
  extensions, and `Obfuscated<D>` interface. Applications add it as a regular
  dependency.
- [`tomgen`](tomgen/) provides the TOML-first executable and the `build_runner`
  generator. Applications add it as a development dependency.
- [`example`](example/) is a runnable package that keeps TOML in an external
  `config/` directory, adds it to the build graph, and verifies the generated
  registries with integration tests.

See the [tomgen setup guide](tomgen/README.md) for complete installation and
usage instructions.

## Environment values

A whole TOML string beginning with `$` can read the environment of the
`build_runner` process:

```toml
url = "$API_URL"
region = "$REGION=us-east"
label = "$$REGION"
```

- `$API_URL` requires `API_URL` and fails generation when it is absent.
- `$REGION=us-east` uses `REGION` when present and `us-east` when absent.
- `$$REGION` generates the literal string `$REGION` without a lookup.

References must occupy the whole string. Text such as `prefix-$VAR` stays
literal. Defaults split at the first `=`, are not recursively expanded, and can
be empty. Resolved text is converted to the target `String`, `int`, `double`, or
`bool` constructor parameter before generation and optional obfuscation.

Environment values are embedded into generated constants. Changing only an
environment variable might not invalidate build_runner's asset graph. To
guarantee regeneration after such a change, run:

```sh
dart run build_runner clean
dart run build_runner build
```

This package does not read `.env` files.

## Supported field types

Registry constructors can use `String`, `int`, `double`, `bool`, Dart enums,
const nested model classes, and one-dimensional `List<T>` values whose element
type is a supported leaf or nested model. A nested model must be a concrete,
non-generic class with a const unnamed constructor containing only named
parameters. Nullable forms are accepted for present values. When an optional
nullable parameter is absent from TOML, the generated call omits it so its Dart
default applies; a `required T?` parameter remains required because TOML has no
synthetic null value.

Enum values are case-sensitive TOML strings that exactly match Dart member
names. TOML arrays become typed constant lists, and environment references can
appear as individual string items:

```toml
tier = "production"
transports = ["$PRIMARY_TRANSPORT=https", "grpc"]
```

An environment reference cannot represent or split into an entire list.
Nested lists, arbitrary maps, sets, records, generic or cyclic models, factory
or positional construction, and TOML date/time values are not supported.
Registry keys must remain scalar or enum values. `@Obfus` is limited to
supported root scalar fields and cannot appear on objects, lists, enums, or
fields inside a nested model.

## Obfuscation limits

`@Obfus` is reversible obfuscation. It keeps readable plaintext out of a simple
`strings` or `grep` scan of generated source and compiled artifacts. The decode
algorithm and key material ship with the application, so a determined person
can recover the original value. Do not use it as a secret store.

TOML can repeat the policy as checked metadata:

```toml
[__tomg]
obfuscate = ["url"]
```

Only top-level constructor field names are accepted. The list is file-wide,
order-independent, and must match the Dart `@Obfus` field set exactly.

## Development and verification

The repository is a Pub workspace. From its root:

```sh
dart pub get
dart analyze
dart test tomg
dart test tomgen
dart run build_runner build --workspace
dart test example
```

See [PUBLISHING.md](PUBLISHING.md) for package dry runs and the required
`tomg`-before-`tomgen` release order.

## License

MIT. See [LICENSE](LICENSE).

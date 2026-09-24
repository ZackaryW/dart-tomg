# tomgen

The TOML-first CLI and `build_runner` generator for **dart-tomg**. It can infer
complete annotated Dart model libraries from a root `g.toml`, then compile the
configured TOML rows into typed `const` registries. The annotation-driven
model-first workflow remains supported.

`tomgen` is a `dev_dependency` - it runs at build time only and never ships
in your app.

## Setup

In your package's `pubspec.yaml`:

```yaml
dependencies:
  tomg: ^0.2.0

dev_dependencies:
  build_runner: ^2.16.1
  tomgen: ^0.2.0
```

`tomgen`'s builder applies automatically. A package-level `build.yaml` is only
needed when a TOML source outside `lib/` must be added to the build graph.

## Initialize a package

After adding the dependencies, create a complete starter configuration:

```sh
dart run tomgen init
```

This creates:

- `g.toml` with an `items` target and `lib/generated` output
- `config/items.toml` with one usable row keyed by `id`
- `build.yaml` coverage for the external TOML source

The command only prepares inputs. It does not run generation, edit
`pubspec.yaml`, declare Flutter assets, or create an ownership manifest. A
second identical invocation is a no-op and reports the reused files.

To initialize from an existing TOML source:

```sh
dart run tomgen init \
  --source config/api_endpoints.toml \
  --target api_endpoints \
  --model ApiEndpoint \
  --key id \
  --output lib/generated
```

`--source`, `--target`, `--model`, and `--key` must be supplied together;
`--output` defaults to `lib/generated`. The command validates dependency
placement, package-contained paths, target and Dart identifiers, TOML model
inference, build input coverage, and every destination before writing. Missing
dependencies produce exact `dart pub add` commands. Existing matching files are
reused, while conflicting files stop the operation without partial changes.

The initializer creates one target. Add more targets, defaults, enums, or
obfuscation metadata by editing the strict version-1 manifest and TOML directly
as described below.

## Generate models from TOML

For manual setup or additional targets, create or edit `g.toml` beside
`pubspec.yaml`:

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

[targets.service_plans.enums.transports]
name = "Transport"
values = ["https", "grpc"]
```

Each lower snake case target produces `<output>/<target>.dart`. `source` is
package-relative, `model` is the Dart class name, and `key` selects the registry
map key. The manifest is strict and versioned; unknown keys, invalid identifiers,
source paths outside the allowed project boundary, and output paths outside
`lib/` fail before files change.

Run both phases:

```sh
dart run tomgen build
```

Or run and clean phase one independently:

```sh
dart run tomgen generate
dart run tomgen clean
```

`tomgen build -- <arguments>` forwards arguments after `--` to
`dart run build_runner build`. Phase two does not start when model generation
fails, and its exit status is returned unchanged.

### Inference rules

- `String`, `int`, `double`, and `bool` infer directly.
- Mixed integer and double evidence widens to `double`.
- Homogeneous one-dimensional arrays infer `List<T>` across all rows.
- Nested tables and inline tables infer const nested model classes.
- Arrays of tables and arrays of inline tables infer `List<Model>` and merge
  item fields across every item and row.
- A field present in every row is required.
- A field missing from any row becomes nullable and optional.
- A compatible value under `[targets.<target>.defaults]` instead produces a
  non-nullable optional parameter with that default.
- Strings become enums only through
  `[targets.<target>.enums.<field>]`, which declares the enum `name` and full
  `values` list. This works for scalar and list fields, including enum keys.
- Environment references remain strings during model inference. An explicit
  enum declaration establishes enum intent; phase two resolves and validates
  its value.

Nested model names are deterministic and path-derived. A `database.tls` object
under root model `Service` becomes `ServiceDatabaseTls`; a `replicas` array of
tables becomes `List<ServiceReplicasItem>`. Nested models are emitted in the
same generated library with const unnamed constructors. Only the root receives
`@TomgRegistry`.

Defaults and enums can address nested leaves through quoted dotted keys:

```toml
[targets.services.defaults]
"database.port" = 5432

[targets.services.enums."replicas.transport"]
name = "Transport"
values = ["https", "grpc"]
```

Every generation infers a fresh graph from the current `g.toml` and TOML
sources. There is no field-type section, lock file, or refresh command. A
structural TOML edit therefore updates the next generated Dart API directly.

Empty registries, all-empty lists without enum evidence, incompatible shapes,
unknown hint paths, object or collection keys, nested lists, and unsupported
obfuscation targets fail with target, table, and complete field-path context.

### Package-local TOML outside lib

For sources such as `config/api_endpoints.toml`, make the directory visible to
build_runner without declaring it as a runtime asset. `tomgen init` handles its
selected source automatically; the equivalent manual configuration is:

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

Phase one emits an `asset:<package>/<source>` annotation and does not copy the
TOML into `lib/`.

### TOML outside the package

A package inside a pub workspace may share committed TOML from elsewhere under
the nearest enclosing workspace root. Given this layout:

```text
workspace/
  pubspec.yaml
  config/tenants.toml
  apps/consumer/
    pubspec.yaml
    g.toml
```

`apps/consumer/g.toml` can declare:

```toml
[targets.tenants]
source = "../../config/tenants.toml"
model = "Tenant"
key = "code"
```

Phase one emits the package-root-relative path and a SHA-256 digest in the
generated `@TomgRegistry`. Phase two reads the external file directly and
verifies that digest before parsing. Normalized paths and resolved symlinks must
remain inside the workspace root. Outside a pub workspace, sources remain
package-contained.

No `build.yaml` entry or Flutter runtime asset is needed for a workspace-external
source. Commit the TOML and generated model so a fresh clone can run plain
`build_runner build`. Because build_runner cannot watch a file outside its asset
graph, always run `dart run tomgen build` after editing external TOML; a stale or
missing source otherwise fails with that regeneration instruction.

### Generated-file ownership

tomgen stores paths and SHA-256 hashes in
`.dart_tool/tomgen/manifest.json`. It writes model outputs as one manifest-last
transaction, preserves unchanged timestamps, removes verified stale outputs,
and refuses to overwrite handwritten or edited files. An identical generated
model checked into source control is adopted without being rewritten when a
fresh clone creates its local manifest. `tomgen clean` removes only verified
phase-one model files; use `dart run build_runner clean` for `.g.dart` files.

## Write the model yourself

`lib/api_endpoint.dart`:

```dart
import 'package:tomg/tomg.dart';

part 'api_endpoint.g.dart';

@TomgRegistry('api_endpoint.toml', key: 'id')
class ApiEndpoint implements Obfuscated<ApiEndpointDeobf> {
  const ApiEndpoint({
    required this.id,
    required this.name,
    @Obfus() required this.url,
    this.visible = true,
  });

  final String id;
  final String name;

  @Obfus()
  final String url;

  final bool visible;

  @override
  ApiEndpointDeobf get deobf => ApiEndpointDeobf(this);
}

const Map<String, ApiEndpoint> endpointRegistry = $ApiEndpoint;
```

`lib/api_endpoint.toml` (next to the class - never a bundled asset, only a
build input):

```toml
[__tomg]
obfuscate = ["url"]

[us-east]
id = "us-east"
name = "US East"
url = "https://api.us-east.example.com"

[staging]
id = "staging"
name = "Staging"
url = "https://staging.example.com"
visible = false
```

Each top-level TOML table becomes one `const` instance, keyed by the `key`
field named in the annotation. A table may omit a field that has a default
in the constructor - the class default applies. A field required by the
constructor must be present in every table, or the build fails naming the
class, field, and table.

TOML keys must match constructor parameters exactly, and registry key values
must be unique. Unknown fields and duplicate keys fail generation with the
source and table names rather than producing incomplete or ambiguous output.

### Declare obfuscation in TOML

The optional reserved metadata table makes the Dart policy visible to TOML
reviewers:

```toml
[__tomg]
obfuscate = ["url"]
```

When this table is present, its unique string field names must equal the class's
`@Obfus` field names exactly, regardless of order. TOML cannot activate
obfuscation on its own: a listed field still needs `@Obfus` on the Dart field,
and every annotated field must appear in the TOML list. Unknown fields,
duplicates, unsupported field types, missing annotations, and missing TOML
declarations fail before registry output is generated.

The table is optional. Files without it retain Dart-only annotation behavior.
`__tomg` is a reserved top-level table name; rename any registry entry using
that name before upgrading. Metadata is consumed only during generation and is
never emitted into the registry or runtime assets.

### Obfuscated registry keys

The registry key may be an obfuscated `String`, `int`, or supported `double`.
The generated map uses the ciphertext as its key, so callers encode plaintext
candidates before lookup:

```dart
final tenant = tenantRegistry[TomgCodec.encodeString(accessCode)];
final region = regionRegistry[TomgCodec.encodeInt(regionId)];
```

The original key is available through the generated decoded companion. This is
reversible obfuscation intended to prevent simple plaintext scans, not a secret
store.

### Supported field types

`tomgen` supports these constructor parameter types:

- `String`, `int`, `double`, and `bool`
- Dart enums represented by exact, case-sensitive member names
- Nullable forms of supported scalar and enum types
- Concrete non-generic nested classes with const unnamed constructors and only
  named parameters
- One-dimensional `List<T>` values of supported scalars, enums, or nested
  models

For example:

```dart
enum Tier { production, staging }

class Service {
  const Service({
    required this.id,
    required this.tier,
    required this.database,
    required this.transports,
    this.note,
  });

  final String id;
  final Tier tier;
  final Database database;
  final List<String> transports;
  final String? note;
}

class Database {
  const Database({required this.host, this.port = 5432});
  final String host;
  final int port;
}
```

```toml
[primary]
id = "primary"
tier = "production"
database = { host = "db.example" }
transports = ["https", "grpc"]
```

This generates `tier: Tier.production`, a
`const <String>["https", "grpc"]` list, and no `note:` argument so the Dart
default applies. A missing `required String?` remains an error: nullability does
not remove the constructor's `required` contract, and TOML has no null literal.

The model-first generator accepts local, unprefixed imported, and prefixed
imported nested classes. It recursively validates nested values and reports
dotted paths plus list indices. Nested lists, arbitrary maps, sets, generic or
cyclic models, factories, positional constructors, and TOML date/time values
remain unsupported. A registry key can be a supported scalar or enum, but not
an object or collection. `@Obfus` supports root scalar strings and numbers;
booleans, enums, objects, lists, and fields inside nested models are rejected
contextually.

### Environment values

Use a whole TOML string of `$VAR` to require a variable from the build process
environment, or `$VAR=default` to provide a fallback:

```toml
url = "$API_URL"
retries = "$RETRIES=3"
enabled = "$FEATURE_ENABLED=false"
literal = "$$API_URL"
```

`$API_URL` fails generation if the variable is absent. Defaults split at the
first `=`, can be empty, and are literal rather than recursively expanded. An
environment variable that is present with an empty value wins over its default.
`$$` escapes a leading dollar, so `$$API_URL` generates `$API_URL` without a
lookup. Dollar signs elsewhere in a string are unchanged.

Resolved values are converted to the constructor parameter type: `String`,
base-10 `int`, `double`, or exact lowercase `true`/`false` for `bool`.
Resolution happens before registry-key collision checks and before `@Obfus`
encoding.

Inside a TOML array, each string item is resolved independently against the
list's element type:

```toml
transports = ["$PRIMARY_TRANSPORT=https", "grpc"]
```

One string such as `transports = "$TRANSPORTS"` cannot stand for a list and is
not split on commas or another delimiter.

The resolved value is embedded in generated Dart. When only the process
environment changes, build_runner might reuse cached output because environment
variables are not tracked assets. Run `dart run build_runner clean` before the
next build to guarantee regeneration. `tomgen` does not read `.env` files.

## Build a hand-written model

```
dart run build_runner build
```

This produces `lib/api_endpoint.g.dart`:

```dart
part of 'api_endpoint.dart';

const Map<String, ApiEndpoint> $ApiEndpoint = <String, ApiEndpoint>{
  "us-east": ApiEndpoint(
    id: "us-east",
    name: "US East",
    url: "Mkjll1xXlzukCWuDPoCjBDtP5clKFdl5tRVngyic4w==", // ciphertext, not the URL
  ),
  "staging": ApiEndpoint(
    id: "staging",
    name: "Staging",
    url: "Mkjll1xXlzu2DWPKIp3pTz9E8IpfAd06phZv",
    visible: false,
  ),
};

class ApiEndpointDeobf {
  const ApiEndpointDeobf(this._o);
  final ApiEndpoint _o;
  String get id => _o.id;
  String get name => _o.name;
  String get url => _o.url.deobf; // decoded
  bool get visible => _o.visible;
}
```

`endpointRegistry['us-east']!.url` is the ciphertext (the `const`, at rest).
`endpointRegistry['us-east']!.deobf.url` is
`"https://api.us-east.example.com"`, decoded at runtime.

## Where the TOML can live

`source` takes two forms:

- A relative path, resolved from the **annotated file's own directory** -
  `'api_endpoint.toml'` above is this form. `'../config/api_endpoint.toml'`
  works too, for a sibling directory.
- A `package:` URI, resolved from the **package's `lib/` root** regardless
  of where the annotated class lives - the same rule `package:` imports
  already follow:

  ```dart
  @TomgRegistry('package:my_app/config/feature_flags.toml', key: 'id')
  class FeatureFlag { ... }
  ```

  finds `lib/config/feature_flags.toml`, even though the class itself might
  be declared in `lib/feature_flags.dart` - useful when several registries
  share one `config/` directory instead of sitting next to each class.

An `asset:package/path` URI is also accepted, resolved from the package
**root** rather than `lib/`, for a TOML that lives outside `lib/` entirely.
`build_runner` only scans `lib/` (plus `bin/`, `web/`, `test/`) by default,
so the consuming package's own `build.yaml` must add that location to its
build `sources:` for `asset:` to find it.

[`example/lib/generated/service_plans.dart`](https://github.com/ZackaryW/dart-tomg/blob/main/example/lib/generated/service_plans.dart),
[`example/config/service_plans.toml`](https://github.com/ZackaryW/dart-tomg/blob/main/example/config/service_plans.toml),
and [`example/build.yaml`](https://github.com/ZackaryW/dart-tomg/blob/main/example/build.yaml)
demonstrate the `asset:` form end to end while keeping TOML outside `lib/`.

## The one line you write by hand

`build_runner` generators can only emit top-level symbols into a `part` file
- they cannot inject a member into your hand-written class. So `tomgen`
generates the `ApiEndpointDeobf` companion, but `implements
Obfuscated<ApiEndpointDeobf>` and the `deobf` getter are written by hand (as
in the class above). This is the whole contract; see
[`tomg`'s README](https://pub.dev/packages/tomg) for the `Obfuscated<D>`
interface it satisfies.

## Errors

`tomgen` fails the build (writing no output) and reports:
- the referenced TOML file doesn't exist as a build input,
- the TOML doesn't parse,
- reserved `__tomg` metadata is malformed or disagrees with Dart `@Obfus`,
- a table is missing a field the constructor requires,
- a table contains a field with no matching constructor parameter,
- two tables use the same registry key, or
- an obfuscated `double` cannot be emitted as a finite, bit-preserving Dart
  constant,
- a required environment variable is absent,
- an environment reference is malformed, or
- an environment value cannot be converted to its constructor parameter type.

## A full working example

[`example/`](https://github.com/ZackaryW/dart-tomg/tree/main/example) is a
complete, real package built this way. It keeps TOML under `config/`, generates
an endpoint registry with matching TOML and Dart obfuscation declarations, and
generates a service-plan registry with enum keys, nested objects, arrays of
tables, lists, and nullable fields. Run `dart run tomgen build && dart test`
inside it to reproduce it from scratch.
`tomgen`'s own [package `example/`
directory](https://pub.dev/packages/tomgen/example) points here.

## License

MIT - see [LICENSE](https://github.com/ZackaryW/dart-tomg/blob/main/tomgen/LICENSE).

# dart-tomg example

This runnable package declares its model targets in root `g.toml` and keeps TOML
build inputs in `config/`, outside `lib/`. `tomgen` generates annotated models
under `lib/generated/`, then build_runner compiles the data into Dart constants.
The TOML files are never declared as runtime assets.

The checked-in package is the expanded, multi-target form of the initializer
workflow. In a clean package, the first target can be prepared with:

```sh
dart run tomgen init \
  --source config/api_endpoints.toml \
  --target api_endpoints \
  --model ApiEndpoint \
  --key id
```

This example then adds `service_plans` plus defaults, enums, and obfuscation
metadata directly in `g.toml` and the TOML files. Running `tomgen init` against
the completed example intentionally reports a conflict because initialization
does not merge into an established manifest.

It contains two focused registries:

- `ApiEndpoint` demonstrates scalar fields, defaults, environment fallback,
  TOML obfuscation metadata, a ciphertext-keyed registry, generated `@Obfus`
  declarations, ciphertext storage, and typed decoded access.
- `ServicePlan` demonstrates enum keys, scalar and enum lists, an
  environment-backed list item, and an optional nullable field.

From the repository root:

```sh
dart pub get
cd example
dart run tomgen build
dart test
dart run bin/example.dart
```

To inspect phase one independently:

```sh
dart run tomgen generate
dart run tomgen clean
dart run tomgen generate
```

The root manifest contains both example targets:

```toml
version = 1
output = "lib/generated"

[targets.api_endpoints]
source = "config/api_endpoints.toml"
model = "ApiEndpoint"
key = "id"
```

Defaults and enum intent are declared in the remaining target tables in
[`g.toml`](g.toml).

The generated annotation uses an `asset:` URI because the TOML is outside
`lib/`:

```dart
@TomgRegistry(
  'asset:dart_tomg_example/config/service_plans.toml',
  key: 'tier',
)
```

The API endpoint TOML declares obfuscation next to its data:

```toml
[__tomg]
obfuscate = ["id", "url"]
```

Phase one generates matching Dart `@Obfus` declarations. Phase two checks that
agreement, excludes metadata and TOML table names from the registry, keys the
map by the encoded `id`, stores ciphertext in `endpoint.id` and `endpoint.url`,
and exposes the original values through the decoded companion. Encode a lookup
candidate with `TomgCodec.encodeString(id)` before indexing the map.

The consumer's `build.yaml` makes external TOML visible to build_runner. The
initializer adds the selected file automatically; this example widens that
entry to `config/**` for both targets:

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

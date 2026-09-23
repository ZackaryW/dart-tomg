# tomg

Runtime for **dart-tomg**: annotations consumed by
[`tomgen`](https://pub.dev/packages/tomgen), the `Obfuscated<D>` interface,
and the reversible codec behind `.deobf`.

`tomg` is a regular (`dependencies:`) package - the only part of it an app
actually calls at runtime is decoding (`.deobf`). Compiling TOML into `const`
Dart and encoding `@Obfus` fields is `tomgen`'s job, at build time.

## What this is for

`dart-tomg` compiles a build-input TOML file into a `const` Dart registry,
optionally storing chosen fields as ciphertext instead of plaintext so they
don't appear as readable bytes in a shipped build artifact (`main.dart.js`,
`libapp.so`, a native/desktop binary). This is **obfuscation, not
encryption**: it defeats a `strings`/`grep` pass over the artifact, not a
determined reverse-engineer.

## Usage

Add both packages (see
[`tomgen`'s README](https://pub.dev/packages/tomgen) for the full setup)
and annotate a class:

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

  // The one line you write by hand: build_runner generators can only emit
  // top-level symbols into a part file, never a member of this class, so
  // `tomgen` generates `ApiEndpointDeobf` but you declare this getter
  // yourself.
  @override
  ApiEndpointDeobf get deobf => ApiEndpointDeobf(this);
}
```

The build-input TOML can optionally repeat the policy for review and drift
checking:

```toml
[__tomg]
obfuscate = ["url"]

[us-east]
id = "us-east"
name = "US East"
url = "https://api.us-east.example.com"
```

When present, `tomgen` requires this list to match the Dart `@Obfus` fields
exactly. The metadata does not replace the annotations or the
`Obfuscated<D>` contract, and it is not emitted into generated Dart.

`tomgen` generates `api_endpoint.g.dart` containing a `const Map<String,
ApiEndpoint>` (with `url` stored as ciphertext) and the `ApiEndpointDeobf`
companion class.

Generator fields may be supported scalars, Dart enums, nullable scalar or enum
types, or one-dimensional lists of those values. Enum names match TOML strings
exactly, and optional omitted nullable parameters keep their Dart defaults. See
[`tomgen`'s setup guide](https://pub.dev/packages/tomgen) for the complete type
matrix and collection limits.

At the call site:

```dart
final endpoint = endpointRegistry['us-east']!;
endpoint.url;        // ciphertext - the const, at rest
endpoint.deobf.url;  // "https://api.us-east.example.com" - decoded, at runtime
```

`endpoint.deobf.url` is **not** usable in a `const` context - decoding only
happens at runtime. `endpoint.url` (the ciphertext) stays a real `const`.

## What's exported

- `@TomgRegistry(source, {required key})` - marks a class as `tomgen`'s
  generation target.
- `@Obfus()` - marks a field as obfuscated.
- `Obfuscated<D>` - the interface an annotated class implements to expose its
  generated decode companion `D` via `deobf`.
- `TomgCodec` - the reversible, deterministic encode/decode codec (`tomgen`
  calls the encode side at build time).
- `.deobf` - extension getters on `String`, `int`, and `double` that decode a
  single ciphertext value produced by `TomgCodec`.

See [`example/`](https://pub.dev/packages/tomg/example) for a minimal,
standalone, runnable demo of these pieces, and the
[full end-to-end example](https://github.com/ZackaryW/dart-tomg/tree/main/example)
in this repo for a real generated registry.

## License

MIT - see [LICENSE](https://github.com/ZackaryW/dart-tomg/blob/main/tomg/LICENSE).

## 0.1.0

Initial release.

- `@TomgRegistry(source, {required key})` and `@Obfus()` annotations,
  consumed by [`tomgen`](https://pub.dev/packages/tomgen) to generate a
  `const` registry from a TOML file.
- `Obfuscated<D>` - the interface an annotated class implements to expose a
  generated decode companion via `deobf`.
- `TomgCodec` - a reversible, deterministic codec for `String`, `int`, and
  `double` (obfuscation, not encryption: defeats `strings`/`grep` on a
  shipped build artifact, not a determined reverse-engineer).
- `.deobf` extension getters on `String`, `int`, and `double` that decode a
  ciphertext value produced by `TomgCodec`.
- Bit-level round-trip coverage for signed zero, finite boundaries, infinities,
  and NaN payloads.
- Documentation for `tomgen`'s optional TOML-side `[__tomg]` obfuscation
  declaration, which must match this package's Dart `@Obfus` annotations.

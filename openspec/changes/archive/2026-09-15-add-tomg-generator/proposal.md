## Why

Configuration that today is hand-written as Dart `const` (for example a tenant
allowlist keyed to trusted server URLs) is verbose to maintain and ships its
sensitive values as plaintext bytes in every build artifact — `strings
main.dart.js` or `strings libapp.so` reads them out directly. There is no
lightweight Dart tool that (a) lets that data live as TOML and be compiled into
`const` objects at build time, and (b) obfuscates chosen fields on the way in so
the shipped bytes are not human-readable. `envied` predates minification and
solves a different, security-framed problem; the actual need here is simple
build-time obfuscation of const config.

## What Changes

- Introduce **two published packages**:
  - `tomg` — runtime + annotations: `@TomgRegistry`, `@Obfus`, the
    `Obfuscated<D>` interface, the reversible codec (encode + decode), and the
    `.deobf` extension. A regular dependency; the only part the app calls at
    runtime is decode.
  - `tomgen` — the `build_runner` generator (Builder + `build.yaml`). A
    dev-dependency that reads the annotated class, parses the sibling TOML,
    encodes `@Obfus` fields via `tomg`'s codec, and emits a `.g.dart` `part`.
- **TOML → const objects**: a class annotated `@TomgRegistry('<file>.toml',
  key: '<field>')` gets a generated `const` registry (e.g. `Map<String, T>`)
  built from the TOML, one input file to one `.g.dart` part (1:1).
- **Build-time-only TOML**: the TOML is a build input compiled into source; it
  is never a bundled asset.
- **Field obfuscation**: fields marked `@Obfus()` are stored as ciphertext in
  the generated `const` (still valid compile-time constants) and decoded at
  runtime. The generator emits a typed companion (e.g. `ApiEndpointDeobf`); the
  annotated class declares `implements Obfuscated<ApiEndpointDeobf>` and a one-line
  `deobf` getter, so `x.deobf.field` returns the plaintext with full typing.
- Depend on [`toml`](https://pub.dev/packages/toml) `^0.18.0` (build-time
  parsing only) inside `tomgen`.

## Capabilities

### New Capabilities
- `toml-codegen`: Build-time generation of `const` Dart objects from a
  build-input TOML file, driven by an annotation on an existing Dart class,
  emitting one `.g.dart` `part` per TOML file.
- `field-obfuscation`: Storing selected fields as ciphertext `const` at build
  time and exposing decoded plaintext at runtime through a typed `Obfuscated<D>`
  companion, backed by a reversible codec shared between generator and runtime.

### Modified Capabilities
<!-- None: greenfield packages, no existing specs. -->

## Impact

- **New packages**: `tomg` (runtime, ships) and `tomgen` (generator,
  dev-dependency) within this repo.
- **Dependencies**: `tomgen` adds `build`, `source_gen`, `analyzer`, and `toml`;
  `tomgen` depends on `tomg`. Consumers add `tomg` to `dependencies` and
  `tomgen` + `build_runner` to `dev_dependencies`.
- **Consumer ergonomics**: obfuscated fields hold ciphertext at runtime; reading
  plaintext requires `.deobf`. `const` contexts (const constructors, const maps,
  switch cases) cannot take a decoded value — decode is runtime-only.
- **Scope note**: obfuscation defeats `strings`/`grep`, not a determined
  reverse-engineer; it is not a security control.

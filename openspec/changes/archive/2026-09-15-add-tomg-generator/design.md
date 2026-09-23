## Context

See proposal.md - Why. The work is greenfield Dart packaging plus a
`build_runner` generator. Two constraints shape every decision:

- `build_runner`/`source_gen` generators can emit only top-level symbols into a
  `part` (classes, consts, functions, `extension`s). They **cannot** inject a
  member into a hand-written class.
- The obfuscation goal is defeating `strings`/`grep` on the shipped artifact
  (`main.dart.js`, `libapp.so`, native/desktop binaries) across all platforms
  with no per-backend post-build tooling. It is not a security control.

## Goals / Non-Goals

**Goals:**
- TOML-authored config compiled into `const` Dart, 1:1 file → `part`.
- Chosen fields obfuscated at build time, decoded at runtime, storage stays
  `const`.
- Typed, autocompleting decoded access whose return type is driven by the
  annotated class.

**Non-Goals:**
- Cryptographic secrecy or key management (obfuscation only).
- Aggregate builds (many TOML → one output), runtime asset loading, or a
  standalone (non-`build_runner`) CLI.
- Obfuscating the registry key by default.
- A custom output location for the generated file - it stays a `part` of the
  annotated library, named by `source_gen`'s standard convention (confirmed;
  the customization surface is the *source* TOML's location, not the
  generated part's).

## Decisions

### Two packages: `tomg` (runtime) + `tomgen` (generator)

Mirrors `json_annotation`/`json_serializable`. `tomg` is a regular dependency
holding annotations (`@TomgRegistry`, `@Obfus`), the `Obfuscated<D>` interface,
the codec, and the `.deobf` extension. `tomgen` is a dev-dependency holding the
Builder + `build.yaml`, depending on `tomg`.
*Alternative:* one package — rejected; it would drag `analyzer`/`build`/`toml`
into every app's runtime dependency graph.

### Codec lives in `tomg`, encode and decode together

Encode (build time) and decode (runtime) must be the same algorithm, so one
source of truth. `tomgen` calls `tomg`'s encode; the app calls `.deobf`
(decode). Unused encode code in the runtime is negligible / tree-shaken.
*Alternative:* codec split across both packages — rejected as a divergence risk.

### `source_gen` triggered on the annotated class; TOML read as secondary input

`@TomgRegistry('config.toml', key: 'code')` on the class; the generator reads
the sibling TOML via the build asset reader, then `TomlDocument.parse` (pure,
platform-agnostic). Output is a `part` of the annotated library, so generated
symbols resolve against the hand-written class.
*Alternative:* trigger on the `.toml` as primary input — rejected; the class is
the schema anchor and where `@Obfus` policy lives.

### `@Obfus` marks fields in Dart, not in TOML

Schema and obfuscation policy live on the class; TOML stays pure data, and a
field is obfuscated consistently across every TOML that fills the class.

### Ciphertext-as-const + typed companion via `Obfuscated<D>`

The generated `const` stores ciphertext (a valid compile-time constant). The
generator emits a typed companion (`ApiEndpointDeobf`) exposing obfuscated fields
decoded and others passed through. The hand-written class declares `implements
Obfuscated<ApiEndpointDeobf>` plus a one-line `ApiEndpointDeobf get deobf =>
ApiEndpointDeobf(this);`. This is the only path that yields a *true* override and
`is Obfuscated<D>` polymorphism under the source_gen constraint above.
*Alternatives considered:*
- Extension-only `.deobf` — zero boilerplate, but not an override and loses
  `is Obfuscated<D>` dispatch. Rejected.
- Dart augmentations to inject the getter — zero boilerplate + true override,
  but bets the package on an unstable/evolving language feature. Rejected for
  "minimal."

### Source path: relative or `package:` URI, via `AssetId.resolve`'s existing scheme support

`source` is parsed with `Uri.parse` and resolved with `build`'s own
`AssetId.resolve(uri, from: buildStep.inputId)`. That resolver already
understands two forms with zero code on our side: a schemeless string
resolves relative to `from` (the annotated file), and a `package:` URI
resolves absolutely against the target package's `lib/` root - the same rule
Dart's own `package:` imports follow. So "the TOML doesn't have to sit next
to the class" falls out of a capability `build` already ships, rather than a
new parameter or a custom root-finding scheme.
*Alternative:* a second annotation parameter (e.g. `root: true` or a
`sourceRoot` enum) to pick relative-vs-package-rooted explicitly — rejected;
it would duplicate a distinction the URI scheme already encodes, and
`package:` is the form Dart authors already reach for instinctively.
(An `asset:package/path` URI is also accepted by the same resolver, rooted at
the package root rather than `lib/`, for a TOML outside `lib/` entirely -
noted in the README, not a primary path since `build_runner` only scans
`lib/`, `bin/`, `web/`, `test/` by default.)

### Registry key not obfuscated by default

Obfuscating the key would force lookups to encode incoming keys and would leave
plaintext keys in the map otherwise. Equality on other ciphertext fields already
works decode-free (equal plaintext → equal ciphertext), covering the common
comparison case. Key obfuscation can be revisited if the key itself must hide.

### TOML parser: `toml ^0.18.0`

MIT, TOML 1.1.0, `TomlDocument.parse(String)` is pure and platform-agnostic;
build-time-only dependency of `tomgen`.

## Risks / Trade-offs

- [Obfuscated field holds ciphertext at runtime, surprising a naive reader of
  the class] → the typed `.deobf` companion is the one obvious place to read
  plaintext; document the field semantics.
- [Consumer must hand-write `implements Obfuscated<D>` + the one-line getter, and
  it references a not-yet-generated companion type] → the `part` makes them the
  same library so it resolves post-generation; document the two-line stub as the
  required contract.
- [`.deobf` output cannot be used in a `const` context] → inherent to the
  approach; specs state decode is runtime-only, and equality on ciphertext
  covers the const-comparison case.
- [Obfuscation is not security; someone who runs the app can recover values] →
  scoped explicitly in the proposal and specs.
- [`dart format` / diff noise on generated files] → generated `part` files are
  build outputs, not hand-edited; formatting is deterministic per build.

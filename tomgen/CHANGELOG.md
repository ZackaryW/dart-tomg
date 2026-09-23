## 0.1.0

Initial release.

- `source_gen`/`build_runner` builder triggered by
  [`tomg`](https://pub.dev/packages/tomg)'s `@TomgRegistry` annotation:
  parses a build-input TOML file and generates a `const Map<K, T>` registry,
  one file to one generated `part` (1:1).
- TOML tables map to constructor arguments by name; a table may omit a field
  that has a class default, and a missing required field fails the build
  naming the class, field, and table.
- `@Obfus` fields are encoded to ciphertext at build time via `tomg`'s
  codec, and a typed `<Class>Deobf` companion is generated exposing them
  decoded (and every other field passed through unchanged).
- `source` accepts a plain relative path (resolved from the annotated
  library's directory) or a `package:<pkg>/<path>` URI (resolved from the
  target package's `lib/` root), so the TOML doesn't have to sit next to
  the annotated class.
- Clear build errors, and no partial output, for a missing/unreadable TOML
  file, a TOML parse error, or a missing required field.
- Validation errors for unknown TOML fields, duplicate registry keys, and
  obfuscated doubles that cannot be represented as finite bit-preserving Dart
  constants.
- Pub workspace support keeps local sibling resolution and publishable hosted
  dependency constraints in the same checked-in manifest.
- Build-time environment substitution with required `$VAR`, fallback
  `$VAR=default`, and literal-dollar `$$` syntax; resolved values support every
  scalar field type and flow through key validation and `@Obfus` encoding.
- Nullable scalar and enum declarations while preserving optional defaults and
  required named-argument checks.
- Exact, case-sensitive Dart enum mapping, including enum registry keys and
  duplicate-key validation.
- Typed constant one-dimensional lists of supported scalars and enums, with
  per-item environment substitution and indexed validation errors.
- Clear rejection of collection registry keys, nested lists, and `@Obfus` on
  enum or collection fields.
- Optional reserved `[__tomg]` metadata with `obfuscate = ["field"]`, exact
  agreement checks against Dart `@Obfus`, metadata-safe diagnostics, and no
  generated registry entry or runtime output for the declaration.
- `tomgen` executable with `generate`, `build`, and `clean` commands for a
  two-phase TOML-first workflow configured by root `g.toml`.
- Deterministic model inference for scalars, numeric widening, nullable fields,
  defaults, flat lists, and explicitly declared scalar or list enums.
- Recursive TOML-first inference and const emission for nested tables, inline
  tables, arrays of tables, and model lists, with deterministic path-derived
  model names and no schema lock file.
- Dotted defaults and enum hints for nested leaves, including fields inside
  model-list items.
- Recursive model-first registry generation for local or imported const nested
  classes, with indexed diagnostics and validation for constructors, cycles,
  keys, and obfuscation boundaries.
- Safe generated-model ownership with content hashes, checked-in output
  adoption, atomic multi-file updates, stale cleanup, and edited-file refusal.

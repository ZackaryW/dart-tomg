# Proposal

## Why

Obfuscation policy is currently visible only in the Dart model, so someone
reviewing the TOML cannot tell which plaintext values will be protected in
generated output. An optional TOML declaration can make that intent explicit
near the data while retaining Dart's typed decode contract.

## What Changes

- Accept an optional top-level `[__tomg]` metadata table with
  `obfuscate = ["field", ...]` in a registry TOML file.
- **BREAKING**: Reserve the top-level `__tomg` table name; an existing registry
  entry with that table name must be renamed before adopting this generator.
- Treat metadata as build configuration rather than a registry entry and omit it
  from generated output.
- When metadata is present, require its obfuscated field set to match the Dart
  model's `@Obfus` fields exactly; fail generation for missing or extra names
  rather than silently changing storage behavior.
- Validate the metadata shape, element types, duplicates, unknown keys, unknown
  constructor fields, and unsupported obfuscation targets with source-specific
  diagnostics.
- Keep metadata optional so existing TOML files without a `__tomg` table and
  Dart-only `@Obfus` usage remain compatible.
- Update the runnable example and documentation to show matching TOML and Dart
  declarations and verify ciphertext storage plus decoded access.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `toml-codegen`: Recognize and validate the reserved optional `[__tomg]`
  metadata table without treating it as a registry row.
- `field-obfuscation`: Require exact agreement between TOML `obfuscate` metadata
  and Dart `@Obfus` declarations whenever the TOML declaration is present.

## Impact

The change affects TOML document preprocessing in `tomgen`, generator fixtures,
the external-config example, package READMEs, and changelogs. It does not change
the `tomg` runtime API, the codec, or generated output for metadata-free files.

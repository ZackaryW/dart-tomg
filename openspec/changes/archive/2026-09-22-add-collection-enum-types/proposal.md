# Proposal

## Why

The generator currently accepts only non-nullable scalar constructor parameters, leaving common TOML arrays and domain enums unusable and rejecting otherwise compatible nullable Dart declarations. Supporting these types is the highest-return way to make TOML registries practical without taking on the substantially larger nested-model design.

## What Changes

- Accept nullable forms of supported scalar and enum parameter types while preserving constructor omission and required-argument behavior; TOML does not gain a synthetic null literal.
- Map TOML strings to Dart enum constants with exact, case-sensitive member matching and contextual errors that list allowed members.
- Generate constant `List<T>` values for supported scalar and enum element types, recursively validating each item and reporting its indexed field path.
- Apply environment substitution to individual string-valued list items using the existing scalar rules; an environment reference cannot stand for or be split into an entire list.
- Reject `@Obfus` on enum and collection fields with a clear error; collection obfuscation and decoded collection companions remain outside this change.
- Keep nested const models, maps, sets, nested lists, TOML date/time values, and arrays of tables outside this change.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `toml-codegen`: Extend TOML-to-constructor mapping to nullable supported types, Dart enums, and constant lists of supported scalar or enum elements.
- `field-obfuscation`: Define clear rejection of obfuscation on newly supported enum and collection fields.

## Impact

- `tomgen/lib/src/tomg_generator.dart` will move from display-string scalar branching toward type-aware recursive constant rendering using analyzer type metadata.
- Generator fixtures, the end-to-end example, generated example output, and user documentation will cover nullable declarations, enums, lists, environment-backed list items, and failure paths.
- `tomg` gains no runtime dependency or new annotation, and generated registries remain compile-time constants.
- Existing supported scalar TOML and environment behavior remains compatible.

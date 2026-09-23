# Spec Delta

## ADDED Requirements

### Requirement: Reserved TOML generator metadata

The generator SHALL treat an optional top-level `__tomg` table as build-time
metadata rather than a registry entry. The metadata table SHALL contain exactly
one `obfuscate` key whose value is an array of unique strings, and it SHALL NOT
appear in the generated registry or generated model data.

#### Scenario: Valid metadata is excluded from the registry

- **WHEN** a registry TOML contains `[__tomg]` with a valid `obfuscate` array
- **THEN** the generator processes the declaration before registry rows and does
  not emit a `__tomg` registry entry or metadata value

#### Scenario: Metadata is absent

- **WHEN** a registry TOML has no top-level `__tomg` table
- **THEN** generation preserves the existing row mapping and Dart-only
  obfuscation behavior

#### Scenario: Reserved name is not a table

- **WHEN** the top-level `__tomg` value is not a TOML table
- **THEN** generation fails with an error naming the source and reserved metadata
  key

#### Scenario: Metadata key is missing or unknown

- **WHEN** the `__tomg` table omits `obfuscate` or contains another key
- **THEN** generation fails with an error naming the source and missing or
  unknown metadata key

#### Scenario: Obfuscate metadata has an invalid value

- **WHEN** `obfuscate` is not an array of unique strings
- **THEN** generation fails with an error naming the source and the invalid value
  location without exposing registry field values

#### Scenario: Reserved table name cannot be a registry row

- **WHEN** a TOML document uses `__tomg` as an ordinary registry table
- **THEN** generation interprets it as metadata and reports any metadata schema
  error rather than constructing a registry entry

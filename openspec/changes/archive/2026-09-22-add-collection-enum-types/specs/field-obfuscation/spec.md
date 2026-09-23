# Spec Delta

## ADDED Requirements

### Requirement: Obfuscation rejects enum and collection fields

The generator SHALL reject `@Obfus` on enum and collection fields because the runtime codec and decoded companion contract support scalar strings and numbers only.

#### Scenario: Obfuscated enum is rejected

- **WHEN** a Dart enum field is marked `@Obfus`
- **THEN** generation fails with an error identifying the field path, enum type, and unsupported obfuscation

#### Scenario: Obfuscated list is rejected

- **WHEN** a `List<T>` field is marked `@Obfus`
- **THEN** generation fails with an error identifying the field path, collection type, and unsupported obfuscation

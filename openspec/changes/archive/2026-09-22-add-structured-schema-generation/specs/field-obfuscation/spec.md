# Spec Delta

## MODIFIED Requirements

### Requirement: Obfuscation rejects enum and collection fields

The generator SHALL reject `@Obfus` on enum, collection, or object-valued
fields because the runtime codec and decoded companion contract support scalar
strings and numbers only. It SHALL also reject `@Obfus` on fields declared
inside a nested model because that model has no independent decoded-companion
contract.

#### Scenario: Obfuscated enum is rejected

- **WHEN** a Dart enum field is marked `@Obfus`
- **THEN** generation fails with an error identifying the field path, enum type,
  and unsupported obfuscation

#### Scenario: Obfuscated list is rejected

- **WHEN** a `List<T>` field is marked `@Obfus`
- **THEN** generation fails with an error identifying the field path, collection
  type, and unsupported obfuscation

#### Scenario: Obfuscated object is rejected

- **WHEN** a custom-model field is marked `@Obfus`
- **THEN** generation fails with an error identifying the field path, model type,
  and unsupported obfuscation

#### Scenario: Obfuscation inside nested model is rejected

- **WHEN** a constructor-bound field inside a reachable nested model is marked
  `@Obfus`
- **THEN** generation fails before registry output with the complete path from
  the root model to the annotated nested field

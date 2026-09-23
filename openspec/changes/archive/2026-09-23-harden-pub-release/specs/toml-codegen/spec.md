# Spec Delta

## ADDED Requirements

### Requirement: Unknown TOML fields are rejected

The generator SHALL fail when a table contains a key that does not match a
named parameter of the annotated class's constructor, and the error SHALL
identify the source, table, and unknown field.

#### Scenario: Mistyped optional field

- **WHEN** a TOML table contains an unknown key that resembles or differs from
  an optional constructor parameter
- **THEN** generation fails instead of silently applying the constructor's
  default value

### Requirement: Registry keys are unique

The generator SHALL fail when two TOML tables resolve to equal values for the
field selected as the registry key, and the error SHALL identify the duplicate
key and both offending tables.

#### Scenario: Duplicate key values across tables

- **WHEN** two TOML tables contain the same value for the annotated registry
  key field
- **THEN** generation fails instead of emitting duplicate map entries

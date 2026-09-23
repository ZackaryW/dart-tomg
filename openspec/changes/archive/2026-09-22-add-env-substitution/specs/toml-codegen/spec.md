# Spec Delta

## ADDED Requirements

### Requirement: Environment resolution precedes registry validation

The generator SHALL resolve and convert environment references before creating
constructor arguments, deriving registry keys, and checking registry key
uniqueness.

#### Scenario: Environment-backed registry key

- **WHEN** the annotated key field contains a valid environment reference
- **THEN** the resolved typed value becomes both the generated map key and the
  matching constructor argument

#### Scenario: Resolved keys collide

- **WHEN** references in two tables resolve to equal registry key values
- **THEN** generation fails with the duplicate-key error naming both tables

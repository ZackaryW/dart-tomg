# Spec Delta

## ADDED Requirements

### Requirement: Environment values are resolved before obfuscation

For a field marked as obfuscated whose TOML value is an environment reference,
the generator SHALL resolve and convert the environment value first, then encode
that resolved value with the field's normal codec.

#### Scenario: Obfuscated environment-backed string

- **WHEN** an `@Obfus` string field contains `$SECRET_VALUE` and the variable
  is present
- **THEN** the generated constant contains ciphertext for the resolved value,
  and contains neither the resolved plaintext nor `$SECRET_VALUE`

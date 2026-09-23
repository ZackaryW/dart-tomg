# Spec Delta

## ADDED Requirements

### Requirement: TOML obfuscation declaration agrees with Dart

When a TOML document includes `__tomg.obfuscate`, the generator SHALL require
the unique field names in that array to equal the annotated registry class's
`@Obfus` field names exactly. TOML metadata SHALL NOT enable or disable
obfuscation independently of the Dart annotations.

#### Scenario: TOML and Dart declarations match

- **WHEN** `__tomg.obfuscate` and the class's `@Obfus` annotations name the same
  supported fields regardless of array order
- **THEN** generation succeeds and stores those fields using the existing
  ciphertext and typed companion behavior

#### Scenario: TOML omits a Dart-obfuscated field

- **WHEN** a field has `@Obfus` in Dart but is absent from the TOML `obfuscate`
  array
- **THEN** generation fails before output with an error naming the source and
  field missing from the TOML declaration

#### Scenario: TOML adds an unannotated field

- **WHEN** the TOML `obfuscate` array names a constructor field that lacks
  `@Obfus` in Dart
- **THEN** generation fails before output with an error naming the source and
  field missing the Dart annotation

#### Scenario: TOML names an unknown field

- **WHEN** the TOML `obfuscate` array names no constructor field on the annotated
  class
- **THEN** generation fails before output with an error naming the source, class,
  and unknown field

#### Scenario: TOML names an unsupported obfuscation target

- **WHEN** TOML and Dart both mark a field whose type cannot be obfuscated
- **THEN** generation fails with the existing contextual unsupported-type error
  and emits no partial output

#### Scenario: TOML declaration is optional

- **WHEN** the TOML document has no `__tomg` table
- **THEN** Dart `@Obfus` annotations remain authoritative and generation behaves
  as it did before TOML metadata support

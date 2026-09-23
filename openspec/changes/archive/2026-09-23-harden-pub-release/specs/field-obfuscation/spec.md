# Spec Delta

## ADDED Requirements

### Requirement: Obfuscated double constants preserve supported values

For every `double` value accepted for obfuscation, the generator SHALL emit a
valid finite Dart `double` constant whose runtime decoding reproduces the
original IEEE-754 bit pattern. If the codec output cannot be represented by
such a constant, generation SHALL fail with an error identifying the field and
value.

#### Scenario: Finite value has a representable ciphertext

- **WHEN** an obfuscated TOML float encodes to a finite value that can be
  represented exactly by a Dart source literal
- **THEN** generation emits that literal and decoding it reproduces the
  original floating-point bit pattern

#### Scenario: Ciphertext cannot be represented safely

- **WHEN** an obfuscated TOML float would require a non-finite or non-round-trip
  ciphertext literal
- **THEN** generation fails with a contextual error instead of emitting invalid
  or lossy Dart source

#### Scenario: Signed zero

- **WHEN** positive or negative zero is accepted for obfuscation
- **THEN** decoding the generated constant preserves the zero's original sign

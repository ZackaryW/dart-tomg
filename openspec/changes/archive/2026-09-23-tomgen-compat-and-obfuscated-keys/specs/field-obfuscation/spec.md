## ADDED Requirements

### Requirement: Obfuscated registry key

When the field named as the registry key is marked as obfuscated, the generator
SHALL key the generated registry map by that field's ciphertext, produced by the
same deterministic codec used for the field value. The plaintext key SHALL NOT
appear anywhere in the generated source. Consumers SHALL be able to look up an
entry by encoding a plaintext candidate with the public runtime codec, without
decoding every entry. The TOML table names SHALL NOT reach the generated source.

#### Scenario: Map keyed by ciphertext

- **WHEN** a registry's key field is a string marked obfuscated
- **THEN** each generated map key is identical to that entry's obfuscated
  key-field ciphertext, and neither the plaintext key nor the TOML table name
  appears in the generated source

#### Scenario: Lookup by encoded plaintext

- **WHEN** consumer code encodes a plaintext key with the public runtime codec
  and indexes the generated registry with the result
- **THEN** it receives the entry whose decoded key equals that plaintext, and
  an encoded value that matches no entry returns no entry

#### Scenario: Decoded key is available through the companion

- **WHEN** consumer code reads the key field through the decoded companion
- **THEN** it receives the original plaintext key

#### Scenario: Duplicate detection still applies

- **WHEN** two tables supply the same plaintext key for an obfuscated key field
- **THEN** generation fails with the existing duplicate-key error, because equal
  plaintext encodes to equal ciphertext

#### Scenario: TOML-first target obfuscates its key

- **WHEN** a TOML-first target's `__tomg.obfuscate` names the target's key field
- **THEN** phase-one generation emits `@Obfus` on that field and phase two
  produces a ciphertext-keyed registry under the same rules

## Purpose

Store selected object fields as obfuscated ciphertext in the generated `const`
so their plaintext never appears in the shipped artifact, while exposing the
decoded values at runtime through a typed companion, keeping storage constant
and decode runtime-only.

## ADDED Requirements

### Requirement: Ciphertext-as-const for marked fields

For each field marked as obfuscated on the annotated class, the generator SHALL
store the field's value as a reversibly encoded ciphertext literal in the
generated `const` construction, such that the plaintext value is absent from the
generated source and the shipped artifact.

#### Scenario: Marked field is stored encoded

- **WHEN** a field is marked obfuscated and its TOML value is a string or number
- **THEN** the generated construction assigns that field a ciphertext literal
  produced by the codec, not the plaintext value

#### Scenario: Plaintext absent from generated source

- **WHEN** the registry is generated with an obfuscated field
- **THEN** the plaintext value does not appear anywhere in the generated source,
  and a byte/string scan of the generated source does not reveal it

#### Scenario: Encoded field remains a compile-time constant

- **WHEN** an obfuscated field is stored as ciphertext
- **THEN** the ciphertext literal is a valid compile-time constant and the
  enclosing construction and collection remain `const`

### Requirement: Reversible codec shared by generator and runtime

The codec SHALL be reversible and deterministic — decoding a value the generator
encoded SHALL reproduce the original plaintext, and equal plaintext SHALL encode
to equal ciphertext — and the same codec SHALL be used to encode at build time
and decode at runtime.

#### Scenario: Round trip preserves value

- **WHEN** a value is encoded by the generator and decoded at runtime
- **THEN** the decoded result equals the original plaintext

#### Scenario: Equal plaintext yields equal ciphertext

- **WHEN** two fields hold the same plaintext value
- **THEN** they encode to identical ciphertext, so equality comparisons on the
  encoded fields hold without decoding

### Requirement: Typed decoded companion

The generator SHALL emit a typed companion for each annotated class that
declares obfuscated fields, exposing each obfuscated field decoded to its
plaintext and each non-obfuscated field unchanged; the annotated class SHALL
expose this companion through the shared `Obfuscated<D>` interface so the return
type is determined by the class.

#### Scenario: Decoded access returns plaintext

- **WHEN** consumer code reads an obfuscated field through the decoded companion
- **THEN** it receives the original plaintext value with the field's declared
  type

#### Scenario: Companion return type is statically the concrete companion

- **WHEN** consumer code accesses the decode entry point on an instance of the
  annotated class
- **THEN** the static type of the result is that class's concrete companion type,
  and the instance satisfies `Obfuscated<D>` for that companion

#### Scenario: Non-obfuscated fields pass through undecoded

- **WHEN** consumer code reads a non-obfuscated field through the companion
- **THEN** it receives the stored value unchanged, without decoding

### Requirement: Decode is runtime-only

Decoding SHALL occur only at runtime; the decoded plaintext SHALL NOT be
required to be a compile-time constant.

#### Scenario: Decoded value is not usable in a const context

- **WHEN** a decoded plaintext value is produced at runtime
- **THEN** it is a runtime value and is not offered as a compile-time constant,
  while the encoded field it derives from remains `const`

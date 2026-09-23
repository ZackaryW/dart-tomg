# field-obfuscation Specification

## Purpose

Store selected object fields as obfuscated ciphertext in the generated `const`
so their plaintext never appears in the shipped artifact, while exposing the
decoded values at runtime through a typed companion, keeping storage constant
and decode runtime-only.

## Requirements

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

### Requirement: Environment values are resolved before obfuscation

For a field marked as obfuscated whose TOML value is an environment reference,
the generator SHALL resolve and convert the environment value first, then encode
that resolved value with the field's normal codec.

#### Scenario: Obfuscated environment-backed string

- **WHEN** an `@Obfus` string field contains `$SECRET_VALUE` and the variable
  is present
- **THEN** the generated constant contains ciphertext for the resolved value,
  and contains neither the resolved plaintext nor `$SECRET_VALUE`

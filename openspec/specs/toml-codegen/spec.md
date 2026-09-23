# toml-codegen Specification

## Purpose

Compile a build-input TOML file into a `const` Dart registry of typed objects,
driven by an annotation on a hand-written class, so configuration lives as TOML
yet ships as compile-time constants and is never a bundled asset.

## Requirements

### Requirement: Annotation-driven registry generation

The generator SHALL, for a Dart class annotated to declare a TOML source file,
produce a generated `part` file containing a `const` collection of instances of
that class, one generated `part` per annotated class (1:1). The annotation SHALL
name the TOML source file and the field used as the collection key.

#### Scenario: Class annotated with a TOML source

- **WHEN** a class `T` is annotated with the registry annotation naming
  `config.toml` and a key field, and `config.toml` exists as a build input
- **THEN** the generator emits a `part` file declaring a `const Map<K, T>` whose
  entries are `const T(...)` instances constructed from the TOML tables, keyed by
  the named key field's value

#### Scenario: Generated collection is a compile-time constant

- **WHEN** the registry is generated
- **THEN** every entry is a `const` construction of the annotated class and the
  collection itself is `const`, usable in `const` contexts

### Requirement: TOML-to-instance mapping

The generator SHALL map each TOML table to one instance of the annotated class,
matching TOML keys to the class's constructor parameters by name and converting
supported TOML values to type-compatible Dart constant expressions. Supported
parameter types SHALL include `String`, `int`, `double`, `bool`, Dart enums
represented by TOML strings, nullable forms of those types, and one-dimensional
`List<T>` values whose element type is a supported scalar or enum. Other
collection and model types SHALL fail generation with a contextual
unsupported-type error.

#### Scenario: Field names and types map by name

- **WHEN** a TOML table contains scalar keys matching the annotated class's
  supported scalar constructor parameters
- **THEN** each value is passed to the matching parameter with a type-compatible
  Dart string, integer, float, or boolean literal

#### Scenario: Nullable scalar or enum receives a present value

- **WHEN** a TOML table supplies a value for a nullable supported scalar or enum
  constructor parameter
- **THEN** the generator renders the value using its non-nullable underlying type
  in the generated constant construction

#### Scenario: Omitted optional field uses its default

- **WHEN** a TOML table omits a key that corresponds to an optional constructor
  parameter, including an optional nullable parameter
- **THEN** the generated construction omits that argument so the class default
  applies

#### Scenario: Missing required nullable field remains an error

- **WHEN** a TOML table omits a key required by the annotated class's constructor,
  even when that parameter's type is nullable
- **THEN** the generator fails the build with an error identifying the class,
  missing field, and offending TOML table

#### Scenario: Missing required field is an error

- **WHEN** a TOML table omits a key required by the annotated class's constructor
- **THEN** the generator fails the build with an error identifying the class,
  the missing field, and the offending TOML table

#### Scenario: Enum member maps by exact name

- **WHEN** a TOML string exactly and case-sensitively matches a member of the
  constructor parameter's Dart enum type
- **THEN** the generator emits that enum constant as the constructor argument

#### Scenario: Unknown enum member is rejected

- **WHEN** a TOML string does not exactly match a member of the target Dart enum
- **THEN** generation fails with an error identifying the source, table, field,
  invalid member, enum type, and allowed member names

#### Scenario: Enum registry key

- **WHEN** the annotation's registry key parameter is an enum and every table
  supplies a valid enum member
- **THEN** the generated registry has that enum key type, emits enum constants as
  keys, and detects duplicate resolved enum keys

#### Scenario: Supported TOML array becomes a constant list

- **WHEN** a TOML array supplies values compatible with a one-dimensional
  `List<T>` parameter whose element type is a supported scalar or enum
- **THEN** the generator emits a typed constant Dart list whose elements retain
  TOML order and keeps the enclosing object and registry compile-time constant

#### Scenario: Environment references resolve per list element

- **WHEN** a string item inside a supported TOML array uses the
  environment-reference syntax
- **THEN** the generator resolves and converts that item against the list element
  type before rendering the constant list

#### Scenario: Environment reference cannot represent a whole list

- **WHEN** a `List<T>` field receives one TOML string containing an environment
  reference instead of a TOML array
- **THEN** generation fails with a list type mismatch and does not split the
  environment value into elements

#### Scenario: Invalid list item reports its index

- **WHEN** an item in a TOML array cannot be converted to the declared list
  element type
- **THEN** generation fails with an error identifying the source and the table,
  field, and zero-based item index

#### Scenario: Nested list is unsupported

- **WHEN** a parameter or TOML value requires a nested list
- **THEN** generation fails with a contextual unsupported-type error rather than
  emitting invalid Dart

#### Scenario: Collection registry key is unsupported

- **WHEN** the annotation selects a `List<T>` parameter as the registry key
- **THEN** generation fails with a clear error identifying that collection-valued
  registry keys are unsupported

### Requirement: Source path resolution

The annotation's source path SHALL support two forms: a relative path,
resolved from the annotated library's own directory; and a `package:` URI,
resolved from the target package's `lib/` root regardless of where the
annotated class lives.

#### Scenario: Relative source path

- **WHEN** the annotation names a plain relative path and a TOML file exists
  at that path relative to the annotated library's directory
- **THEN** the generator resolves and reads that file

#### Scenario: Package-relative source path

- **WHEN** the annotation names a `package:<package>/<path>` URI and a TOML
  file exists at `<path>` under that package's `lib/` directory
- **THEN** the generator resolves and reads that file, regardless of which
  directory the annotated class's own library file is in

### Requirement: Build-time-only TOML input

The TOML source SHALL be consumed only at build time and its data SHALL appear
only inside generated Dart source; the generator SHALL NOT require the TOML file
to be a bundled runtime asset.

#### Scenario: TOML data present only in generated source

- **WHEN** the build completes
- **THEN** the configuration values are present in the generated `.g.dart`
  source and the build does not depend on the TOML file being declared as a
  runtime asset

### Requirement: Malformed input reporting

The generator SHALL report a clear build error, rather than emitting invalid
Dart, when the TOML source cannot be parsed or the referenced source file is
absent.

#### Scenario: Unparseable TOML

- **WHEN** the referenced TOML file contains a syntax error
- **THEN** the generator fails the build with an error naming the file and the
  parse problem, and no partial `part` file is emitted

#### Scenario: Referenced source file missing

- **WHEN** the annotation names a TOML file that does not exist as a build input
- **THEN** the generator fails the build with an error naming the missing file

### Requirement: Reserved TOML generator metadata

The generator SHALL treat an optional top-level `__tomg` table as build-time
metadata rather than a registry entry. The metadata table SHALL contain exactly
one `obfuscate` key whose value is an array of unique strings, and it SHALL NOT
appear in the generated registry or generated model data.

#### Scenario: Valid metadata is excluded from the registry

- **WHEN** a registry TOML contains `[__tomg]` with a valid `obfuscate` array
- **THEN** the generator processes the declaration before registry rows and does
  not emit a `__tomg` registry entry or metadata value

#### Scenario: Metadata is absent

- **WHEN** a registry TOML has no top-level `__tomg` table
- **THEN** generation preserves the existing row mapping and Dart-only
  obfuscation behavior

#### Scenario: Reserved name is not a table

- **WHEN** the top-level `__tomg` value is not a TOML table
- **THEN** generation fails with an error naming the source and reserved metadata
  key

#### Scenario: Metadata key is missing or unknown

- **WHEN** the `__tomg` table omits `obfuscate` or contains another key
- **THEN** generation fails with an error naming the source and missing or
  unknown metadata key

#### Scenario: Obfuscate metadata has an invalid value

- **WHEN** `obfuscate` is not an array of unique strings
- **THEN** generation fails with an error naming the source and the invalid value
  location without exposing registry field values

#### Scenario: Reserved table name cannot be a registry row

- **WHEN** a TOML document uses `__tomg` as an ordinary registry table
- **THEN** generation interprets it as metadata and reports any metadata schema
  error rather than constructing a registry entry

## Purpose

Compile a build-input TOML file into a `const` Dart registry of typed objects,
driven by an annotation on a hand-written class, so configuration lives as TOML
yet ships as compile-time constants and is never a bundled asset.

## ADDED Requirements

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
TOML scalar types to the corresponding Dart field types.

#### Scenario: Field names and types map by name

- **WHEN** a TOML table contains keys matching the annotated class's constructor
  parameters
- **THEN** each value is passed to the matching parameter with a type-compatible
  Dart literal (string, integer, float, boolean)

#### Scenario: Omitted optional field uses its default

- **WHEN** a TOML table omits a key that corresponds to a constructor parameter
  with a default value
- **THEN** the generated construction omits that argument so the class default
  applies

#### Scenario: Missing required field is an error

- **WHEN** a TOML table omits a key required by the annotated class's constructor
- **THEN** the generator fails the build with an error identifying the class,
  the missing field, and the offending TOML table

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

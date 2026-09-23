# Spec Delta

## MODIFIED Requirements

### Requirement: TOML-to-instance mapping

The generator SHALL map each TOML table to one instance of the annotated class,
matching TOML keys to the class's constructor parameters by name and converting
supported TOML values to type-compatible Dart constant expressions. Supported
parameter types SHALL include `String`, `int`, `double`, `bool`, Dart enums
represented by TOML strings, nullable forms of those types, supported nested
const model types, and one-dimensional `List<T>` values whose element type is a
supported scalar, enum, or model. A supported model SHALL be a concrete,
non-generic class with a const unnamed constructor containing only named
parameters whose types are recursively supported. Other types SHALL fail
generation with a contextual unsupported-type error.

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

#### Scenario: Nested table constructs a const model

- **WHEN** a supported custom-model parameter receives a TOML table or inline
  table whose keys satisfy that model's constructor
- **THEN** the generator emits a constant constructor expression of that model
  and recursively converts its fields

#### Scenario: Imported nested model resolves in library context

- **WHEN** a nested model type is local, imported without a prefix, or imported
  with a prefix in the annotated library
- **THEN** the generated part uses a type reference valid in that library's
  import context

#### Scenario: Array of tables constructs List of model

- **WHEN** a `List<Model>` parameter receives an array of tables or inline
  tables compatible with the supported model constructor
- **THEN** the generator emits a typed constant list of constant model
  constructor expressions in TOML order

#### Scenario: Empty declared model list is supported

- **WHEN** a `List<Model>` parameter receives an empty TOML array
- **THEN** the generator emits a typed empty constant list using the declared
  Dart item type

#### Scenario: Invalid nested value reports its full path

- **WHEN** a nested object or model-list item contains an unknown, missing, or
  incompatible value
- **THEN** generation fails before output with the source, registry table, and a
  dotted path containing every applicable list index

#### Scenario: Recursive model cycle is rejected

- **WHEN** reachable custom model constructors form a direct or indirect type
  cycle
- **THEN** generation fails with the involved type path instead of recursing
  indefinitely

#### Scenario: Nested list is unsupported

- **WHEN** a parameter or TOML value requires a nested list
- **THEN** generation fails with a contextual unsupported-type error rather than
  emitting invalid Dart

#### Scenario: Collection registry key is unsupported

- **WHEN** the annotation selects a `List<T>` parameter as the registry key
- **THEN** generation fails with a clear error identifying that collection-valued
  registry keys are unsupported

#### Scenario: Object registry key is unsupported

- **WHEN** the annotation selects a custom-model parameter as the registry key
- **THEN** generation fails with a clear error identifying that object-valued
  registry keys are unsupported

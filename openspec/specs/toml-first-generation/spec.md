# toml-first-generation Specification

## Purpose

Generate complete Dart model libraries from project-level TOML targets and run
their existing registry generation safely through one command-line workflow.

## Requirements

### Requirement: Root generation manifest

The CLI SHALL discover the nearest ancestor containing `pubspec.yaml` as the
package root and SHALL read a versioned `g.toml` from that root. The manifest
MUST declare `version = 1`, an output directory beneath `lib/`, and one or more
named targets containing a package-relative TOML `source`, Dart `model`, and
registry `key`. Target names SHALL be lower snake case and SHALL determine the
generated `<target>.dart` filename. Unknown, missing, duplicate, malformed, or
unsupported configuration SHALL fail before any output changes.

#### Scenario: Manifest is discovered from a package subdirectory

- **WHEN** a user runs a tomgen CLI command below a package root containing a
  valid `pubspec.yaml` and `g.toml`
- **THEN** the CLI uses that package root and resolves every manifest path from
  it

#### Scenario: Manifest version is unsupported

- **WHEN** `g.toml` declares a version other than `1`
- **THEN** the CLI fails with an error naming the manifest and unsupported
  version and writes no generated file

#### Scenario: Configured output escapes lib

- **WHEN** the normalized or canonical output path is outside the package's
  `lib/` directory
- **THEN** the CLI rejects the manifest before reading target data or modifying
  output

#### Scenario: Configured source escapes the package

- **WHEN** a normalized or canonical target source is outside the package root
- **THEN** the CLI rejects the target with its name and source path and modifies
  no generated file

#### Scenario: Target configuration is invalid

- **WHEN** a target omits a required key, uses an invalid target or Dart
  identifier, or contains an unknown configuration key
- **THEN** the CLI fails with the manifest location and target context rather
  than silently ignoring the configuration

### Requirement: Deterministic flat schema inference

For each target, the CLI SHALL infer one deterministic flat model schema from
all non-metadata top-level TOML tables. It SHALL support `String`, `int`,
`double`, `bool`, and one-dimensional homogeneous lists of those scalar types;
mixed `int` and `double` observations SHALL infer `double`. A field present in
every row SHALL be required. A field omitted by any row SHALL be nullable and
optional unless the target declares a compatible default, in which case it
SHALL be non-nullable and optional with that default. Conflicting or unsupported
shapes SHALL fail with target, table, and field context.

#### Scenario: Consistent fields infer required scalar types

- **WHEN** every row supplies a field with values of one supported scalar type
- **THEN** the generated schema contains a required field of that Dart type

#### Scenario: Integers and doubles widen to double

- **WHEN** a field contains integer values in some rows and double values in
  others
- **THEN** the generated schema uses `double` and the later registry generator
  can render every observed value without loss of type compatibility

#### Scenario: Missing field becomes nullable

- **WHEN** a supported field is absent from at least one row and has no declared
  default
- **THEN** the generated schema declares a nullable field and an optional named
  constructor parameter

#### Scenario: Compatible default replaces nullability

- **WHEN** a field is absent from at least one row and `g.toml` declares a
  default compatible with all observed values
- **THEN** the generated schema declares a non-nullable optional parameter with
  that constant default

#### Scenario: List element type is inferred across rows

- **WHEN** a field contains one-dimensional arrays whose combined non-empty
  items have one compatible supported scalar type
- **THEN** the generated schema uses `List<T>` with that element type and keeps
  source item order for phase-two generation

#### Scenario: Empty lists provide no element evidence

- **WHEN** every observed value for a non-enum list field is empty
- **THEN** inference fails with the target and field because no list element
  type can be determined

#### Scenario: Incompatible observations are rejected

- **WHEN** one field has incompatible scalar types, mixes a scalar and list, has
  nested lists, or contains a TOML table or date/time value
- **THEN** inference fails with the target, table, field, and conflicting shapes
  and changes no generated output

### Requirement: Explicit enum declarations

A target MAY declare an enum for a scalar string field or a list-of-strings
field by providing a valid Dart enum name and a non-empty list of unique valid
Dart member names. The CLI SHALL use that declaration instead of a string type
and SHALL reject literal TOML values or defaults outside the declared members.
Environment-reference strings SHALL remain subject to phase-two environment
resolution and enum validation.

#### Scenario: Scalar string field becomes an enum

- **WHEN** a target declares an enum for a scalar string field and every literal
  value is an allowed member
- **THEN** the generated library declares the enum and types the model field as
  that enum

#### Scenario: String list becomes an enum list

- **WHEN** a target declares an enum for a one-dimensional string-list field
- **THEN** the generated library declares the enum and types the model field as
  `List<EnumName>`

#### Scenario: Enum registry key is allowed

- **WHEN** the configured registry key has a valid scalar enum declaration
- **THEN** the generated annotation and model permit the existing generator to
  create an enum-keyed registry

#### Scenario: Enum value is outside the declaration

- **WHEN** a literal field value or configured default is not one of the
  declared enum members
- **THEN** the CLI fails with the target, field, invalid value, and allowed
  members

#### Scenario: Conflicting enum declarations reuse a name

- **WHEN** two fields in one generated library use the same enum name with
  different member lists
- **THEN** the CLI rejects the target instead of emitting an ambiguous Dart
  declaration

### Requirement: Complete generated model library

The CLI SHALL generate a formatted Dart library for each target containing a
generated-file notice, the `tomg` import, a `.g.dart` part directive, any enum
declarations, an annotated model with a const named-parameter constructor, and
a public `<lowerCamelModelName>Registry` alias for the phase-two registry. The
annotation SHALL use an `asset:` URI containing the package name and configured
source path. The generated library SHALL contain model structure and metadata,
but SHALL NOT embed registry row values.

#### Scenario: Basic target generates a build_runner input library

- **WHEN** `tomgen generate` processes a valid target
- **THEN** its output is a formatted Dart library that analyzes after its
  declared `.g.dart` part is generated

#### Scenario: External TOML stays a build-time input

- **WHEN** a target source is outside `lib/`
- **THEN** the model annotation references it with a package-root `asset:` URI
  and the CLI does not copy the TOML into `lib/` or declare it as a runtime asset

#### Scenario: Registry alias is deterministic

- **WHEN** the model is named `ApiEndpoint`
- **THEN** the generated library exposes
  `const Map<KeyType, ApiEndpoint> apiEndpointRegistry = $ApiEndpoint`

### Requirement: TOML obfuscation produces the Dart contract

When a target source contains valid `__tomg.obfuscate` metadata, phase-one
generation SHALL emit matching `@Obfus` annotations and the complete
`Obfuscated<...>` decoded-access contract required by the existing phase-two
generator. Unsupported or unknown obfuscation fields SHALL fail before any
output change.

#### Scenario: Obfuscated scalar field is generated automatically

- **WHEN** `__tomg.obfuscate` names a supported string or numeric model field
- **THEN** the generated constructor parameter and field carry `@Obfus`, the
  model implements its generated companion type, and its `deobf` getter returns
  that companion

#### Scenario: Obfuscation target is unsupported

- **WHEN** metadata names an enum, list, unknown, or otherwise unsupported field
- **THEN** phase-one generation fails with the target and field and does not
  leave Dart annotations that phase two cannot satisfy

#### Scenario: Metadata is absent

- **WHEN** a target source has no `__tomg` table
- **THEN** the generated model contains no `@Obfus` fields or decoded-access
  contract

### Requirement: Safe generated-file ownership

The CLI SHALL write model libraries atomically and track their paths and content
hashes in `.dart_tool/tomgen/manifest.json`. It SHALL overwrite or delete a path
only when both the generated-file notice and ownership manifest identify the
unchanged file. A failed multi-target generation SHALL leave the previous model
files and ownership manifest unchanged, and successful generation SHALL avoid
rewriting files whose content is unchanged.

#### Scenario: Handwritten destination already exists

- **WHEN** a target output path exists without verified tomgen ownership
- **THEN** generation fails without overwriting that file

#### Scenario: Owned file was edited

- **WHEN** an owned generated file's current hash differs from its recorded
  content hash
- **THEN** generation fails and preserves the edited file for the user to
  reconcile

#### Scenario: Target removal cleans an unmodified stale file

- **WHEN** a target is removed from `g.toml` and its prior output remains
  verified and unchanged
- **THEN** the next successful generation deletes that stale model library and
  removes it from the ownership manifest

#### Scenario: Generation fails before commit

- **WHEN** any configured target fails parsing, inference, validation, formatting,
  or ownership checks
- **THEN** no target output or manifest from the previous successful generation
  is changed

#### Scenario: Generated content is unchanged

- **WHEN** a generated library is byte-for-byte equal to the owned file on disk
- **THEN** generation leaves that file untouched while retaining its ownership
  record

### Requirement: Safe project initialization

The `tomgen init` command SHALL initialize the discovered Dart package through a
noninteractive, all-or-nothing operation. With no target options it SHALL create
a valid starter `g.toml`, an external `config/items.toml` containing one usable
row keyed by `id`, and build graph coverage for that source. With target options
it SHALL instead reference an existing package-contained TOML source using the
provided lower-snake-case target, Dart model, registry key, and an optional
output directory that defaults beneath `lib/`. It SHALL validate package
dependencies, paths, identifiers, TOML input, manifest content, and every file
conflict before changing the package.

#### Scenario: Zero-argument initialization creates a working starter

- **WHEN** a user runs `dart run tomgen init` in an otherwise uninitialized
  package with the required dependencies
- **THEN** the package receives a version-1 `g.toml`, a starter
  `config/items.toml`, build input coverage for that source, and inputs that can
  be passed directly to `tomgen build`

#### Scenario: Existing source initializes a custom target

- **WHEN** a user runs `tomgen init` with a contained existing TOML source and
  valid target, model, and key options
- **THEN** the generated manifest contains exactly that target, uses
  `lib/generated` unless another contained output is selected, and does not
  replace or copy the source file

#### Scenario: External source becomes a build input rather than an asset

- **WHEN** the initialized target reads TOML outside `lib/`
- **THEN** initialization creates or extends the package build configuration so
  build_runner can read the source without adding it to Flutter runtime assets

#### Scenario: Compatible build configuration is preserved

- **WHEN** `build.yaml` already has supported target configuration and either
  covers the source or can accept an additional source entry
- **THEN** initialization preserves unrelated builders, targets, source entries,
  ordering, and comments while making only the required build-input change

#### Scenario: Required package dependency is missing or misplaced

- **WHEN** `tomg`, `tomgen`, or `build_runner` is absent from its required
  dependency section
- **THEN** initialization fails before writing and reports the exact dependency
  correction commands

#### Scenario: Existing destination conflicts with the scaffold

- **WHEN** `g.toml`, a starter source, or build configuration cannot be reused or
  safely extended without replacing user-authored content
- **THEN** initialization exits nonzero, identifies every conflicting path, and
  leaves all package files byte-for-byte unchanged

#### Scenario: Initialization input is invalid

- **WHEN** an option is missing, unknown, contradictory, escapes the package, or
  would produce an invalid manifest or model target
- **THEN** initialization reports the option or path error and changes no file

#### Scenario: Repeated initialization is idempotent

- **WHEN** the package already contains the exact scaffold or equivalent build
  input coverage produced by the same initialization request
- **THEN** initialization succeeds without rewriting any file and reports the
  existing initialized state

#### Scenario: Successful initialization reports the next command

- **WHEN** initialization succeeds with created or reused inputs
- **THEN** the CLI lists the created and unchanged paths and prints
  `dart run tomgen build` as the next step from the package root

### Requirement: Generate, build, and clean commands

The `tomgen` executable SHALL expose `init`, `generate`, `build`, and `clean`.
`init` SHALL perform safe package initialization without running model or
registry generation. `generate` SHALL perform phase-one model generation only.
`build` SHALL complete phase one and then invoke
`dart run build_runner build` from the package root, forwarding arguments after
`--`, standard input/output, and the child exit status. It SHALL not start phase
two after a phase-one failure. `clean` SHALL remove only unchanged phase-one
files proven by the ownership manifest and SHALL NOT remove build_runner-owned
`.g.dart` files.

#### Scenario: Init performs scaffolding only

- **WHEN** a user runs `dart run tomgen init` with valid inputs
- **THEN** project inputs are initialized without generating model libraries,
  registry parts, or an ownership manifest

#### Scenario: Generate performs phase one only

- **WHEN** a user runs `dart run tomgen generate`
- **THEN** model libraries and the ownership manifest are updated without
  invoking build_runner

#### Scenario: Build runs both phases in order

- **WHEN** a user runs `dart run tomgen build` with valid inputs
- **THEN** all model libraries are committed before build_runner starts and the
  existing generator produces their `.g.dart` parts

#### Scenario: Phase one blocks phase two

- **WHEN** model generation fails for any target
- **THEN** `tomgen build` exits nonzero without invoking build_runner

#### Scenario: Build runner failure is propagated

- **WHEN** phase one succeeds but build_runner exits nonzero, including when an
  external TOML source is absent from the package build graph
- **THEN** `tomgen build` returns that failure while preserving the generated
  model source for diagnosis

#### Scenario: Clean preserves unowned and edited files

- **WHEN** `tomgen clean` encounters an unowned path or an owned file whose hash
  changed
- **THEN** it does not delete that file and reports the conflict

### Requirement: Existing model-first workflow remains available

The new executable SHALL be additive. Packages MAY continue writing annotated
models by hand and running build_runner directly without a `g.toml`, and CLI
generation SHALL affect only targets declared by the discovered manifest.

#### Scenario: Existing package runs build_runner directly

- **WHEN** a package has hand-written `@TomgRegistry` models and no `g.toml`
- **THEN** the existing builder continues generating registries with its current
  public API and behavior

#### Scenario: Handwritten and generated models coexist

- **WHEN** a package contains hand-written annotated models outside the
  manifest output paths and generated targets inside them
- **THEN** build_runner processes both sets while CLI ownership operations are
  limited to the manifest-generated model files

# Spec Delta

## ADDED Requirements

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

## MODIFIED Requirements

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

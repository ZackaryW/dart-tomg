# external-toml-sources Specification

## Purpose

Allow TOML-first packages in a pub workspace to compile shared, committed TOML
sources outside the package while preserving bounded filesystem access,
deterministic generation, and fresh-clone reproducibility.

## Requirements

### Requirement: External sources are bounded by the enclosing pub workspace

The TOML-first CLI SHALL allow a target source outside the package only when the
package belongs to an enclosing pub workspace and both the normalized and
canonical source paths remain inside the nearest such workspace root. It SHALL
reject absolute paths, lexical escapes, and symlink escapes beyond that boundary.
When no enclosing pub workspace exists, the package root SHALL remain the source
boundary.

#### Scenario: Source at the workspace root is accepted

- **WHEN** a workspace package configures a relative source outside the package
  but inside its nearest enclosing pub workspace
- **THEN** phase one reads that source and generates the target model

#### Scenario: Lexical escape leaves the workspace

- **WHEN** a configured source normalizes to a path outside the nearest
  enclosing pub workspace
- **THEN** phase one rejects the target before modifying generated output

#### Scenario: Symlink escape leaves the workspace

- **WHEN** a configured source lexically remains in the workspace but resolves
  through a symlink to a path outside it
- **THEN** phase one rejects the target before reading the external file

#### Scenario: Standalone package keeps its package boundary

- **WHEN** a package without an enclosing pub workspace configures a source
  outside its package
- **THEN** phase one rejects the source under the existing package-only rule

### Requirement: External source content is digest-pinned between phases

For an accepted external source, phase one SHALL emit the normalized
package-root-relative source path and a digest of the exact source bytes in the
generated registry annotation. The digest SHALL use the form
`sha256:<64 lowercase hexadecimal characters>`. Editing the external source and
rerunning phase one SHALL update the generated annotation.

#### Scenario: Phase one emits an external source digest

- **WHEN** phase one generates a model from an accepted external TOML source
- **THEN** its registry annotation contains the package-root-relative source and
  the SHA-256 digest of that source's exact bytes

#### Scenario: External source content changes

- **WHEN** an external TOML source changes and phase one runs again
- **THEN** the generated annotation contains the new digest and is treated as a
  normal owned-file content update

### Requirement: Phase two verifies external sources before generation

When a registry annotation carries an external-source digest, phase two SHALL
resolve the source from the annotated package root, enforce the same workspace
boundary, read it directly from the filesystem, and verify its digest before
parsing. A missing source, malformed digest, boundary violation, or digest
mismatch SHALL fail without partial output and SHALL instruct the user to rerun
`dart run tomgen build`. An external source without a digest SHALL be rejected.

#### Scenario: Matching external source generates a registry

- **WHEN** phase two finds an external source inside the workspace whose digest
  matches the annotation
- **THEN** it parses the source and generates the registry normally

#### Scenario: External source is stale

- **WHEN** the external source bytes no longer match the annotation digest
- **THEN** phase two fails without partial output and directs the user to rerun
  `dart run tomgen build`

#### Scenario: External source is missing

- **WHEN** an annotation carries a digest but its external source is absent
- **THEN** phase two fails with the source path and regeneration instruction

#### Scenario: Digest is malformed

- **WHEN** an annotation digest does not use the required SHA-256 form
- **THEN** phase two rejects it before parsing source content

#### Scenario: External path has no digest

- **WHEN** an annotation names a source outside the package without a digest
- **THEN** phase two rejects the unpinned filesystem read

### Requirement: Existing package-local source behavior remains compatible

Package-local TOML-first targets SHALL retain their current annotation source,
build-runner asset reads, and generated output without emitting a digest.
Existing model-first annotations that omit the optional digest SHALL retain
their current API and behavior.

#### Scenario: Package-local target is regenerated

- **WHEN** phase one processes an existing package-local target
- **THEN** its generated model is byte-identical to the pre-change output and
  its annotation contains no digest

#### Scenario: Existing model-first annotation omits digest

- **WHEN** build_runner processes an existing registry annotation created with
  only a source and key
- **THEN** phase two resolves and reads the source through the existing build
  asset path

### Requirement: Checked-in external sources support fresh-clone builds

A committed external TOML source and its committed digest-bearing generated
model SHALL allow phase two to run through plain build_runner without a phase-one
rerun. Editing an external source SHALL require `tomgen build` to refresh the
digest before the change can be compiled.

#### Scenario: Fresh clone runs build_runner directly

- **WHEN** a fresh checkout contains the committed external TOML and matching
  generated model but no prior local generation state
- **THEN** plain build_runner generation succeeds

#### Scenario: User edits external TOML

- **WHEN** a user changes an external TOML source
- **THEN** running `tomgen build` refreshes the generated model digest before
  invoking phase two

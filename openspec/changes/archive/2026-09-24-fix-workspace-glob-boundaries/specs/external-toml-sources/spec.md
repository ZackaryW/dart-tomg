# Spec Delta

## MODIFIED Requirements

### Requirement: External sources are bounded by the enclosing pub workspace

The TOML-first CLI SHALL allow a target source outside the package only when the
package belongs to an enclosing pub workspace through either an explicit member
path or a supported workspace glob and both the normalized and canonical source
paths remain inside the nearest such workspace root. It SHALL reject absolute
paths, lexical escapes, and symlink escapes beyond that boundary. A workspace
declaration that does not match the package SHALL NOT grant access to the
workspace boundary. When no enclosing pub workspace exists, the package root
SHALL remain the source boundary.

#### Scenario: Source at the workspace root is accepted

- **WHEN** a workspace package configures a relative source outside the package
  but inside its nearest enclosing pub workspace
- **THEN** phase one reads that source and generates the target model

#### Scenario: Glob-selected workspace member is accepted

- **WHEN** an enclosing workspace selects the package through a supported glob
  and the package configures a source inside that workspace
- **THEN** phase one uses the enclosing workspace as the source boundary and
  generates the target model

#### Scenario: Nonmatching workspace glob grants no boundary

- **WHEN** an ancestor workspace contains glob declarations that do not select
  the package
- **THEN** phase one retains the package boundary and rejects a source outside
  the package

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

### Requirement: Phase two verifies external sources before generation

When a registry annotation carries an external-source digest, phase two SHALL
resolve the source from the annotated package root, enforce the same explicit
or glob-selected workspace boundary as phase one, read it directly from the
filesystem, and verify its digest before parsing. A missing source, malformed
digest, boundary violation, or digest mismatch SHALL fail without partial output
and SHALL instruct the user to rerun `dart run tomgen build`. An external source
without a digest SHALL be rejected.

#### Scenario: Matching external source generates a registry

- **WHEN** phase two finds an external source inside the workspace whose digest
  matches the annotation
- **THEN** it parses the source and generates the registry normally

#### Scenario: Glob-selected member generates a registry

- **WHEN** phase two processes a digest-bearing model whose package is selected
  by a workspace glob and whose source remains inside that workspace
- **THEN** it accepts the same boundary as phase one and generates the registry

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

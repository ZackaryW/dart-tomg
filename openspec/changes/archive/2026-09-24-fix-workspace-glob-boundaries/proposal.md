# Proposal

## Why

Tomgen treats each Pub workspace member declaration as a literal path when it
discovers the source boundary. Valid Dart 3.11+ workspace globs such as
`apps/*` therefore leave member packages with a package-only boundary and
incorrectly reject shared TOML sources stored elsewhere in the workspace.

## What Changes

- Recognize Pub workspace glob declarations when determining whether a package
  belongs to an enclosing workspace.
- Preserve canonical path and symlink containment checks after a glob matches.
- Verify glob-member external sources through both phase-one model generation
  and phase-two build_runner generation.
- Add repository-level consumer coverage for glob members, nonmatching globs,
  and sources that escape through paths or symlinks.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `external-toml-sources`: Workspace boundary discovery accepts packages
  selected by a Pub workspace glob while retaining existing containment rules.

## Impact

- `tomgen/lib/src/cli/project.dart` workspace boundary discovery.
- Phase-one CLI configuration and phase-two builder behavior that share the
  boundary helper.
- Unit and black-box CI fixtures for workspace-contained external TOML.
- No public Dart API or dependency change is required.

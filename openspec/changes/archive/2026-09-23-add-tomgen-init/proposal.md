# Proposal

## Why

Starting the TOML-first workflow currently requires users to hand-create a
valid `g.toml`, arrange an initial TOML source, and expose external configuration
to build_runner correctly. A safe `tomgen init` command can make the first
working registry reproducible while preserving the CLI's existing strict path
and ownership guarantees.

## What Changes

- Add a noninteractive `tomgen init` command that discovers the package root and
  creates a valid version-1 generation manifest plus the build inputs needed for
  a first target.
- Support a zero-argument starter mode and an existing-source mode with explicit
  target, model, and key options so initialization works for both exploratory
  and established packages.
- Configure external TOML sources in the package build graph without declaring
  them as runtime assets, preserving compatible existing `build.yaml` content.
- Preflight every destination and configuration change before writing anything;
  matching files are reusable, while conflicting or unsupported project state
  fails without partial initialization or overwrites.
- Report created and reused files, detected dependency problems, and the exact
  `tomgen build` command to run next.
- Keep `generate`, `build`, `clean`, and the hand-written model workflow
  unchanged.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `toml-first-generation`: Add safe project initialization and expose `init` as
  an additive tomgen command.

## Impact

The change affects the tomgen command parser and usage text, project and
manifest scaffolding code, build configuration handling, CLI fixtures, the
runnable example documentation, and package changelog. It may add a focused
YAML editing dependency if preserving existing `build.yaml` formatting cannot
be implemented safely with the current dependencies. It does not change the
tomg runtime API or generated registry format.

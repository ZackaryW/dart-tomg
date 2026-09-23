# Proposal

## Why

Using tomgen currently starts with a hand-written Dart model, even when the TOML
already contains enough structure to describe that model. A project-level
generation manifest and CLI can make TOML the starting point while retaining the
existing typed, const, build_runner output.

## What Changes

- Add a `tomgen` executable with `generate`, `build`, and `clean` commands.
- Add a versioned `g.toml` manifest at the package root for declaring TOML
  sources, generated model names, registry keys, output locations, defaults,
  and enum intent.
- Infer supported scalar, nullable, and one-dimensional list fields from all
  registry rows, with explicit manifest declarations for defaults and enums.
- Generate complete Dart model libraries under `lib/`, including
  `@TomgRegistry`, const constructors, registry aliases, and the `@Obfus` and
  decoded-access contract declared by TOML metadata.
- Make `tomgen build` run model generation first and build_runner second, while
  preserving the existing hand-written-model build_runner workflow.
- Protect handwritten files through generated-file headers, atomic writes, and
  a project-local ownership manifest used for stale cleanup.
- Update the example package to demonstrate the complete TOML-first workflow.
- Keep automatic nested-model inference, arrays of tables, and watch mode out of
  this initial CLI change; nested model support remains a separate active change.

## Capabilities

### New Capabilities

- `toml-first-generation`: Configure, generate, build, and safely clean Dart
  model libraries from project-level TOML targets.

### Modified Capabilities

None.

## Impact

The change affects the `tomgen` package executable, configuration parsing,
schema inference and Dart emission code, package dependencies, CLI tests, the
example package, and setup documentation. `tomg` runtime APIs and existing
annotation-driven projects remain compatible.

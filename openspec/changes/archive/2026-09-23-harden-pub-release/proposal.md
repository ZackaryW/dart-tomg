# Proposal

## Why

The packages demonstrate a useful TOML-to-`const` registry workflow, but the
first public release needs stronger input validation, coverage for numeric
obfuscation edge cases, reproducible package metadata, and a repository landing
page that explains the niche clearly. Addressing these gaps before 0.1.0 reduces
the chance that early adopters receive silently incomplete registries or invalid
generated Dart.

## What Changes

- Reject unknown TOML fields and duplicate generated registry keys with clear,
  contextual generation errors.
- Guarantee that every supported obfuscated `double` produces a valid Dart
  constant and round-trips, including non-finite values and signed zero, or
  reject values that cannot satisfy that contract.
- Add focused generator tests for successful generation and malformed inputs.
- Make the two-package local-development and ordered-publishing workflow
  reproducible without manually rewriting dependency declarations between
  development and release.
- Replace the minimal repository README with a concise use case, example,
  package map, limitations, and release-quality verification instructions.
- Document the explicit build-time environment syntax for required references,
  defaults, escaped dollar prefixes, and rebuild limitations.

## Capabilities

### New Capabilities

- `release-readiness`: Defines a repeatable validation and packaging workflow
  for the coupled `tomg` and `tomgen` releases.

### Modified Capabilities

- `toml-codegen`: Require validation of unknown fields and duplicate registry
  keys instead of silently ignoring or overwriting configuration data.
- `field-obfuscation`: Define valid constant emission and round-trip behavior
  for supported floating-point edge cases.

## Impact

The change affects `tomgen` validation and tests, `tomg` codec tests, package
and workspace metadata, release documentation, and the repository README. It
does not change the public annotations or runtime interfaces in 0.1.0;
environment-reference behavior remains defined by the separate
`environment-substitution` capability.

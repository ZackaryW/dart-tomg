# Spec Delta

## Purpose

Provide maintainers with a repeatable local validation and ordered publishing
workflow for the coupled runtime and generator packages.

## ADDED Requirements

### Requirement: Local development uses publishable dependency declarations

The repository SHALL resolve `tomgen` against the local `tomg` package during
workspace development while retaining a hosted version constraint suitable for
published consumers.

#### Scenario: Resolve the repository workspace

- **WHEN** a maintainer resolves dependencies from the repository workspace
- **THEN** `tomgen` uses the local compatible `tomg` package without requiring
  a path dependency in its publishable manifest

### Requirement: Release validation is documented and repeatable

The repository SHALL document commands that analyze, test, generate, and dry
run publication of both packages in their required release order.

#### Scenario: Prepare the first release

- **WHEN** a maintainer follows the release instructions from a clean checkout
- **THEN** the workflow validates the runtime, generator, end-to-end example,
  and package archives before any irreversible publish command

### Requirement: Package scope and limitations are discoverable

The repository documentation SHALL explain the TOML-to-typed-`const` registry
use case, the roles of both packages, the limits of field obfuscation, and the
explicit build-time environment-reference syntax and rebuild limitations.

#### Scenario: Environment-reference behavior is discoverable

- **WHEN** a user needs an environment value, a fallback, or a literal
  dollar-prefixed string in TOML
- **THEN** the documentation explains `$VAR`, `$VAR=default`, and `$$VAR`, their
  build-time-only resolution, and when a clean regeneration may be required

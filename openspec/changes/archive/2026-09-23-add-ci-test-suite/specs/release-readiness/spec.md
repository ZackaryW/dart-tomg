# Spec Delta

## ADDED Requirements

### Requirement: Dedicated consumer verification package

The workspace SHALL include a non-published `ci_test/` package whose tests run
tomgen from isolated temporary consumer packages rather than relying on the
repository example's pre-existing generated files. The suite SHALL verify the
starter and existing-source initialization modes through generation and Dart
analysis, SHALL confirm external TOML is not declared as a runtime asset, and
SHALL remain outside both published package archives.

#### Scenario: Verify starter initialization as a consumer

- **WHEN** the CI test suite initializes a new package with zero target options
- **THEN** the package builds and analyzes its generated starter model and const
  registry without adding a runtime asset

#### Scenario: Verify custom initialization as a consumer

- **WHEN** the CI test suite initializes an existing external TOML source with
  explicit target, model, and key options
- **THEN** the package builds and analyzes the requested generated model and
  const registry without copying or bundling the source

#### Scenario: Published archives exclude repository integration tests

- **WHEN** a maintainer performs dry-run publication of `tomg` and `tomgen`
- **THEN** neither package archive contains the `ci_test/` package or its
  black-box fixtures

### Requirement: Automated clean-checkout verification

The repository SHALL run automated verification for pull requests, pushes to
the main branch, and manually requested runs using both the minimum supported
Dart SDK and the current stable SDK. Verification SHALL reject formatting or
analysis issues, failing runtime, generator, example, or consumer tests,
non-deterministic checked-in generation, and invalid package archives. The
workflow SHALL expose each failed gate and return a failing job status.

#### Scenario: Pull request passes every verification gate

- **WHEN** a pull request contains formatted, analyzable code with passing tests,
  current generated example output, and valid package archives
- **THEN** automated verification succeeds on the minimum and stable Dart SDKs

#### Scenario: Checked-in generated output is stale

- **WHEN** example regeneration changes a tracked generated file
- **THEN** automated verification fails and exposes the unexpected diff

#### Scenario: Consumer behavior regresses

- **WHEN** starter or custom-source generation no longer builds in an isolated
  consuming package
- **THEN** the dedicated CI test gate fails even if package unit tests pass

#### Scenario: Package archive becomes invalid

- **WHEN** either published package produces a dry-run publication warning or
  error from the clean checkout
- **THEN** automated verification fails before release

## MODIFIED Requirements

### Requirement: Release validation is documented and repeatable

The repository SHALL document a local command sequence that matches the
automated formatting, analysis, package-test, consumer-test, deterministic
generation, and publication dry-run gates, together with the required package
release order.

#### Scenario: Prepare the first release

- **WHEN** a maintainer follows the release instructions from a clean checkout
- **THEN** the workflow validates the runtime, generator, end-to-end example,
  isolated consumer workflows, checked-in generated output, and package archives
  before any irreversible publish command

#### Scenario: Reproduce an automated failure locally

- **WHEN** an automated verification gate fails
- **THEN** the maintainer can run its documented command from the repository
  checkout and observe the same validation behavior

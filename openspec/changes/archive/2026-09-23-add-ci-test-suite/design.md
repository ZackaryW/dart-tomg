# Design

## Context

See `proposal.md` for motivation and the release-readiness delta for required
behavior. The root Pub workspace currently contains `tomg`, `tomgen`, and the
runnable `example`; it has no `.github/workflows` directory or repository-level
CI runner. Release commands live in `PUBLISHING.md` and are executed manually.

The new tomgen initializer already has a real-process integration test in
`tomgen/test/init_e2e_test.dart`. That test creates temporary consumers, resolves
local path dependencies, invokes the CLI and build_runner, and analyzes the
result. Keeping it under `tomgen/test` causes repository-only integration
machinery to enter the published generator archive and makes package tests
responsible for whole-repository topology.

The workspace supports Dart `^3.12.2`, and the default branch is `main`.
External TOML and generated example files are checked in, while Pub and build
artifacts are already ignored.

## Goals / Non-Goals

**Goals:**

- Give repository-only black-box tests a tracked workspace home with no publish
  surface.
- Make the same named verification gates readable in CI output and reproducible
  as local commands.
- Prove minimum-SDK compatibility and detect forward compatibility regressions
  on the current stable SDK.
- Detect stale checked-in generation and package archive warnings from a clean
  checkout.
- Keep pull-request execution read-only and independent of repository secrets.

**Non-Goals:**

- Publishing packages, uploading artifacts, deploying documentation, or writing
  to the repository from CI.
- Adding coverage thresholds, performance benchmarks, or prerelease Dart
  channels in the first workflow.
- Replacing focused unit tests with black-box subprocess tests.
- Installing OpenSpec in CI; OpenSpec validation remains part of planning and
  archive workflows rather than the Dart package release contract.

## Decisions

### 1. Make `ci_test/` a non-published Pub workspace package

The root workspace will add `ci_test` alongside the existing three members.
Its pubspec will use `publish_to: none`, `resolution: workspace`, the same SDK
constraint, and only test-support dependencies such as `path`, `test`, and
`lints`. It will have its own analysis options and README explaining how to run
its tests.

`tomgen/test/init_e2e_test.dart` will move into `ci_test/test/` and retain its
temporary-package approach. The tests will resolve tomg and tomgen from the
current checkout, assert that `init` does not add runtime assets, run
`tomgen build`, inspect model and registry outputs, and run `dart analyze` in
each consumer. The suite will also assert that its source and fixtures are not
present in either dry-run package archive.

This is preferred to a loose `ci_test/` script directory because a workspace
package participates in normal dependency resolution and analysis, can be run
with `dart test ci_test`, and is explicitly excluded from publication. Keeping
the existing test duplicated under tomgen was rejected because it would double
the slow build_runner work and continue shipping repository integration code.

### 2. Keep workflow gates explicit instead of hiding them behind an orchestrator

`.github/workflows/ci.yml` will name and run each command directly:

1. resolve the workspace;
2. check Dart formatting;
3. analyze the workspace;
4. test `tomg`, `tomgen`, and `ci_test`;
5. regenerate and test `example`;
6. fail on a generated-file diff; and
7. dry-run both published packages.

`PUBLISHING.md` and `ci_test/README.md` will list the same commands in the same
order. Explicit steps make the failed contract visible in the GitHub job UI and
avoid a custom runner whose process handling would itself need independent
verification. A single `ci_test.sh` or Dart orchestrator was considered, but it
would collapse logs and introduce another abstraction without reducing the
number of external tools.

### 3. Use a two-SDK matrix with release-only work on the minimum SDK

The primary job matrix will use exact Dart `3.12.2` and the `stable` channel on
`ubuntu-latest`. Both jobs run formatting, analysis, every test package, and
deterministic example generation. The package publication dry-runs run only for
`3.12.2`, because the produced source archives are SDK-independent and the
minimum version is the strongest resolution check for declared compatibility.

Testing only stable was rejected because it can silently raise the effective
minimum SDK. Running all three operating systems and prerelease SDKs was
deferred because build_runner consumer tests are relatively expensive and the
initial requirement is clean-checkout correctness rather than platform matrix
coverage.

### 4. Use a read-only, cancelable GitHub Actions workflow

The workflow will run for pull requests, pushes to `main`, and
`workflow_dispatch`. It will declare `contents: read`, use no secrets, avoid
`pull_request_target`, and cancel an older in-progress run for the same branch
or pull request. It will use the maintained `actions/checkout` major and
`dart-lang/setup-dart@v1`, with the SDK value supplied by the matrix.

The deterministic-generation gate will run the normal example build and then
`git diff --exit-code` over tracked generated example files. The publish gates
run from the clean checkout only after this diff passes, so Pub's dirty-tree
warning remains a real failure signal rather than being suppressed.

### 5. Preserve package-focused tests and archive cleanliness

Unit and component tests stay with the package they test. Only subprocess tests
that require sibling packages or validate package archives belong in
`ci_test/`. Publish dry-runs remain direct `dart pub -C <package> publish
--dry-run` calls without `--ignore-warnings`; any warning fails the release gate.
The workflow will also inspect the dry-run file listing or package validation
output to prove `ci_test/` is absent.

## Risks / Trade-offs

- **[Stable Dart can expose an upstream incompatibility before a dependency is
  ready]** -> Keep minimum and stable jobs separately named so the compatibility
  failure is visible, then update constraints or dependencies deliberately.
- **[Two build_runner consumer passes increase pull-request time]** -> Move the
  tests out of tomgen to avoid duplicate execution and rely on dependency caches
  provided by the hosted runner environment.
- **[Publish dry-runs can depend on pub.dev availability]** -> Run them once per
  workflow and keep unit, analysis, consumer, and generation gates independent
  so an external outage is distinguishable from a code failure.
- **[A moving stable SDK reduces exact reproducibility]** -> Pair it with the
  pinned minimum SDK; stable is an intentional forward-compatibility signal.
- **[Generated diff checks can include unrelated working-tree changes locally]**
  -> Scope the command to checked-in example generation paths and document that
  release dry-runs require a clean checkout.

## Migration Plan

1. Add `ci_test/` to the workspace and move the existing end-to-end initializer
   test without changing its consumer behavior.
2. Run all local gates and both publish dry-runs to establish a clean baseline.
3. Add the GitHub Actions workflow and documentation, then verify its syntax and
   command parity locally.
4. Push the branch and require the workflow in branch protection after its first
   successful run. Rollback removes the workflow and workspace member; package
   source and public APIs are unaffected.

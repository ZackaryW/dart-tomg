# Proposal

## Why

The repository's release checks currently run only when a maintainer invokes
them locally, so pull requests and pushed commits can merge without proving the
workspace, generated example, consumer workflow, or package archives remain
valid. A dedicated CI test package and required GitHub Actions workflow will
make that evidence reproducible from a clean checkout.

## What Changes

- Add a non-published `ci_test/` workspace package for black-box tests that
  exercise tomgen as a consuming project would.
- Move the starter and custom-source `tomgen init` end-to-end coverage out of
  the published `tomgen` package and extend it with CI-specific failure and
  cleanliness assertions.
- Add a GitHub Actions workflow for pull requests, main-branch pushes, and
  manual runs that checks formatting, analysis, package tests, external
  consumer builds, deterministic example regeneration, and publish dry-runs.
- Test the minimum supported Dart SDK and current stable SDK while running
  release archive validation once on the minimum-SDK job.
- Document one local command sequence that matches the automated verification
  gates and makes failures reproducible outside GitHub Actions.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `release-readiness`: Require automated clean-checkout verification and a
  dedicated, non-published consumer test package in addition to the documented
  local release workflow.

## Impact

The change affects the root Pub workspace, test ownership, package archive
contents, release documentation, and a new `.github/workflows/ci.yml` workflow.
It adds a `ci_test/` package but no runtime dependency or published API. GitHub
Actions usage and build time increase because full consumer generation runs on
every supported CI SDK.

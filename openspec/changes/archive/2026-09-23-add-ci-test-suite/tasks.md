# Tasks

## 1. Dedicated CI Test Package

- [x] 1.1 Create the non-published `ci_test/` Dart package with workspace resolution, analysis options, focused test dependencies, and root workspace membership; verify `dart pub get` succeeds and the package is included in workspace analysis.
- [x] 1.2 Move the real-process initializer integration test from `tomgen/test/` into `ci_test/test/` and extend its assertions for starter and custom source builds, generated model and registry analysis, external-source preservation, and absence of runtime assets; verify `dart test ci_test` passes while `dart test tomgen` no longer runs the repository-level fixture.
- [x] 1.3 Add a workflow contract test that parses `.github/workflows/ci.yml` and verifies required triggers, read-only permissions, SDK matrix entries, named verification commands, deterministic-diff gate, and unsuppressed publish dry-runs; verify the test fails against missing or weakened workflow fields and passes against the delivered workflow.

## 2. Automated Workflow

- [x] 2.1 Add `.github/workflows/ci.yml` for pull requests, pushes to `main`, and manual dispatch with read-only contents access, branch-aware concurrency cancellation, Ubuntu execution, and a Dart `3.12.2` plus `stable` matrix; verify the workflow contract test recognizes every trigger and matrix entry.
- [x] 2.2 Add explicit workflow steps for dependency resolution, format checking, workspace analysis, `tomg`, `tomgen`, `ci_test`, and example tests, example regeneration, and scoped generated-file diff detection; verify every command succeeds locally in the documented order and an intentional generated-file edit makes the diff gate fail.
- [x] 2.3 Add minimum-SDK-only `tomg` and `tomgen` publish dry-run steps without warning suppression; verify clean-export dry-runs report zero warnings and their archive listings exclude `ci_test/` and repository-only fixtures.

## 3. Maintainer Documentation

- [x] 3.1 Add `ci_test/README.md` describing the package boundary, black-box cases, direct test command, and relationship to package tests; verify all named files and commands exist.
- [x] 3.2 Update `PUBLISHING.md` and the root README with the local command sequence matching CI, minimum/stable coverage, deterministic-generation check, and package release order; verify the documented commands and workflow steps stay in the same order.

## 4. Verification

- [x] 4.1 Format all Dart files, run workspace analysis, and run `dart test tomg`, `dart test tomgen`, `dart test ci_test`, example regeneration plus tests, and the generated-file diff gate; verify all checks pass from the working checkout.
- [x] 4.2 Run both package publish dry-runs from a clean export and inspect their file lists; verify zero warnings and no `ci_test/` or moved integration fixture appears in either archive.
- [x] 4.3 Run `openspec validate add-ci-test-suite --strict` and `git diff --check`; verify the implementation satisfies every release-readiness scenario before archive.

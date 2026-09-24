# Tasks

## 1. Workspace Membership

- [x] 1.1 Update workspace boundary discovery to match canonical package-relative paths against explicit and glob member declarations while rejecting absolute, invalid, nonmatching, and canonically external candidates; verify focused project and configuration tests pass.
- [x] 1.2 Extend unit coverage for matching glob members, nonmatching globs, literal-member compatibility, and lexical and symlink containment behavior; verify the tests fail against exact-only discovery and pass with glob-aware discovery.

## 2. End-to-End Coverage

- [x] 2.1 Change the isolated external-source consumer fixture to use a glob workspace member and verify `tomgen build` succeeds through phase one and phase two from a clean temporary workspace.
- [x] 2.2 Add negative isolated coverage proving a nonmatching glob and a workspace-contained symlink escape do not grant external source access; verify both commands fail before generated output is accepted.

## 3. Verification

- [x] 3.1 Run stable formatting, workspace analysis, `tomgen` tests, and `ci_test`; verify all checks pass and example generated output remains unchanged.
- [x] 3.2 Run `openspec validate fix-workspace-glob-boundaries --strict` and `git diff --check`; verify every artifact and source change is valid and the task list is complete.

# Tasks

## 1. Command Contract

- [x] 1.1 Add the immutable init request, `init` command parsing, complete and partial custom option handling, forwarding rejection, and updated usage text; verify parser tests cover starter mode, custom mode, help, duplicate and unknown options, positional arguments, and every incomplete option set.
- [x] 1.2 Extract shared target-name and Dart-identifier validation from manifest loading for initializer reuse; verify existing config tests and new direct validator cases accept and reject the same values.

## 2. Initialization Planning

- [x] 2.1 Add structure-preserving YAML and glob dependencies needed by the initializer and verify `dart pub get` succeeds for the workspace without unrelated lockfile changes.
- [x] 2.2 Implement package dependency inspection for `tomg`, `tomgen`, and `build_runner`, including misplaced entries and exact repair commands; verify fixture tests cover scalar, hosted, git, path, workspace, missing, malformed, and wrong-section declarations.
- [x] 2.3 Implement starter and existing-source request validation with package-contained paths, regular `.toml` files, inferred record/key checks, output confinement beneath `lib`, and candidate version-1 manifest construction; verify tests cover valid nested invocation plus invalid identifiers, missing sources, symlink escapes, malformed TOML, absent keys, uninferable rows, and escaping output.
- [x] 2.4 Implement absent and existing `build.yaml` planning with semantic glob coverage and structure-preserving insertion into supported `$default.sources` sequences; verify tests cover file creation, exact and glob reuse, comment/order preservation, unrelated configuration preservation, and rejection of unsupported YAML shapes.
- [x] 2.5 Assemble an `InitializationPlan` that classifies exact scaffold files and semantic build coverage as created or reused while collecting all conflicts before writes; verify tests show a differing `g.toml`, starter source, or incompatible build configuration reports every conflict and leaves the fixture byte-for-byte unchanged.

## 3. Transaction and CLI Integration

- [x] 3.1 Implement temporary sibling writes, observed-state checks, atomic replacement, and rollback for failed commits; verify failure-injection tests restore modified files, remove newly created files and temporary files, and reject concurrent destination drift.
- [x] 3.2 Dispatch `tomgen init` through `TomgenInitializer` and print package-relative created/reused paths, the discovered package root, and `dart run tomgen build`; verify CLI tests cover execution from a nested directory, an idempotent second run, nonzero preflight failure, and absence of generated Dart or ownership files.
- [x] 3.3 Add end-to-end fixtures for zero-argument and custom existing-source initialization, then run `tomgen build`; verify each fixture produces compilable model and registry output while external TOML remains absent from Flutter assets.

## 4. Documentation and Release Verification

- [x] 4.1 Update the root and tomgen READMEs, runnable example setup, and changelog with starter and custom `tomgen init` workflows plus the manual fallback; verify every documented command and path matches the CLI help and example files.
- [x] 4.2 Format changed Dart files and run the workspace analyzer, all package tests, example generation/tests, and both package publish dry-runs; verify every command completes without errors or publish warnings.
- [x] 4.3 Run `openspec validate add-tomgen-init --strict` and verify the completed implementation satisfies every initialization scenario before archiving.

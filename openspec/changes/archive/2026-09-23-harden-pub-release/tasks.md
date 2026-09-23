# Tasks

## 1. Generator Validation

- [x] 1.1 Add builder test infrastructure and a successful TOML-to-registry fixture; verify the focused `tomgen` test passes
- [x] 1.2 Add failing builder fixtures for unknown TOML fields and duplicate registry keys; verify each error names the source, table, and offending field or key
- [x] 1.3 Implement strict unknown-field and duplicate-key validation; verify all `tomgen` builder tests pass

## 2. Floating-Point Obfuscation

- [x] 2.1 Add bit-level codec tests for signed zero, finite boundary values, infinities, and NaN payload behavior; verify the runtime test suite records the supported round trips
- [x] 2.2 Add generator fixtures for safely representable and unsafe encoded doubles; verify generated constants analyze and unsafe values fail contextually
- [x] 2.3 Implement finite, bit-preserving double literal validation in the generator; verify the runtime and generator suites pass

## 3. Reproducible Package Resolution

- [x] 3.1 Add a non-publishable root Pub workspace and opt all three packages into workspace resolution; verify `dart pub get` succeeds at the repository root
- [x] 3.2 Replace local path dependencies with hosted version constraints that resolve to workspace siblings locally; verify `dart pub deps` reports local `tomg` for `tomgen` and the example
- [x] 3.3 Update the ordered release instructions so no manifest rewriting is required; verify the documented commands match the checked-in manifests

## 4. Documentation

- [x] 4.1 Replace the root README with the package purpose, concise example, package roles, obfuscation limits, and validation commands; verify all repository links resolve to existing files
- [x] 4.2 Document `$VAR`, `$VAR=default`, and `$$VAR` build-time behavior plus rebuild limitations in the root and generator READMEs; verify the examples match the environment-substitution contract
- [x] 4.3 Update package changelogs and generator error documentation for the release-hardening behavior; verify the entries match the implemented behavior

## 5. Release Verification

- [x] 5.1 Regenerate the example and run analysis and tests for the workspace packages; verify all commands complete without issues
- [x] 5.2 Run strict OpenSpec validation and both publication dry runs; verify both `tomg` and `tomgen` complete with no package warnings
- [x] 5.3 Inspect the final Git diff for generated artifacts, workspace metadata, and accidental files; verify only intended release files remain

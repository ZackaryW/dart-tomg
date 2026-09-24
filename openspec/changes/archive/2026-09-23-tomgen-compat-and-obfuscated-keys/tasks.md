# Tasks

## 1. Widen and verify generator dependency ranges

- [x] 1.1 In `tomgen/pubspec.yaml`, set `analyzer: '>=10.0.1 <15.0.0'`, `source_gen: '>=4.2.3 <5.0.0'`, and `dart_style: '>=3.1.7 <4.0.0'`; run `dart pub get` and verify the default resolution succeeds.
- [x] 1.2 Run `dart analyze` and `dart test tomgen` on the default resolution and verify analysis is clean and all generator tests pass.
- [x] 1.3 Add `pubspec_overrides.yaml` to `.gitignore` and verify `git check-ignore pubspec_overrides.yaml` succeeds.
- [x] 1.4 Add a Dart 3.12.2 `lowest-bounds` CI job that writes a root override pinning analyzer 10.0.1, source_gen 4.2.3, dart_style 3.1.7, and test 1.31.0; verify the workflow runs resolution, analysis, tomgen tests, ci_test, example generation and tests, and the generated-output diff.
- [x] 1.5 Reproduce the lowest-bounds job from a scratch copy, verify 106 tomgen, 3 ci_test, and 9 example tests pass with no generated diff, and record the reproducible command sequence in `PUBLISHING.md`.

## 2. Contract obfuscated registry keys

- [x] 2.1 Add model-first generator tests for an `@Obfus` key verifying map keys equal ciphertext, plaintext keys and TOML table names are absent, decoded companion access returns plaintext, and duplicate plaintext keys fail.
- [x] 2.2 Add a TOML-first test where `__tomg.obfuscate` names the key field; verify phase one emits `@Obfus`, phase two produces a ciphertext-keyed registry, encoded lookup returns the matching entry, and an unknown encoded value returns null.
- [x] 2.3 Add an "Obfuscated registry keys" README section with string and numeric lookup examples and the reversible-obfuscation caveat; verify every documented API reference analyzes in a test or example.

## 3. Add the digest annotation contract

- [x] 3.1 Add optional `String? digest` to `TomgRegistry` without changing existing constructor calls; verify existing model-first tests compile unchanged and new annotation tests can read the value.
- [x] 3.2 Add digest parsing and validation for the `sha256:<64 lowercase hex>` form; verify malformed algorithm, length, and hex values fail with annotation and source context.
- [x] 3.3 Verify package-local annotations without a digest retain the existing `BuildStep` source-resolution path and byte-identical generated output.

## 4. Resolve workspace-bounded external sources in phase one

- [x] 4.1 Extend project discovery to locate the nearest enclosing `pubspec.yaml` with a `workspace:` declaration containing the package; verify nested invocation selects the package root and the correct workspace root.
- [x] 4.2 Allow a target source outside the package only when both its normalized and canonical paths remain inside that workspace; verify a valid workspace-root source succeeds while lexical escape, symlink escape, and a source outside the workspace fail without writing output.
- [x] 4.3 Preserve the package-only boundary when no enclosing pub workspace exists; verify the same escaping source remains rejected in a standalone package.
- [x] 4.4 For an external source, emit a normalized package-root-relative annotation path and the SHA-256 of the exact TOML bytes; verify editing the TOML changes the digest and phase-one owned-file hash.
- [x] 4.5 Keep package-local targets on their current `asset:` URI without a digest; verify existing emitter goldens remain byte-identical.

## 5. Read and verify external sources in phase two

- [x] 5.1 For a digest-bearing annotation, locate and verify the package root against `buildStep.inputId.package`, resolve the source from that root, and enforce the enclosing workspace's lexical and symlink boundary; verify wrong-package and escaping-path cases fail before reading TOML.
- [x] 5.2 Read a valid external source directly, verify its SHA-256 before parsing, and generate the registry; verify a fresh-clone-style plain `build_runner build` succeeds without rerunning phase one.
- [x] 5.3 Reject a missing external file, malformed digest, digest mismatch, and external path without a digest with an actionable stale-model error naming `dart run tomgen build`; verify no partial generated part is emitted.
- [x] 5.4 Add a `ci_test` consumer in a temporary pub workspace with TOML at the workspace root; verify `tomgen build`, analysis, runtime registry lookup, and external-source non-bundling all succeed.
- [x] 5.5 Verify existing package-local unit, consumer, and example tests still use build-runner assets and produce no generated diff.

## 6. Document and release 0.2.0

- [x] 6.1 Document external sources in the README, including the workspace boundary, digest handoff, fresh-clone behavior, and the requirement to run `tomgen build` after editing external TOML; verify the documented example matches an integration fixture.
- [x] 6.2 Bump `tomg` to 0.2.0, add its digest-annotation CHANGELOG entry, and verify `dart pub -C tomg publish --dry-run` completes without warnings.
- [x] 6.3 Bump `tomgen` to 0.2.0, set its hosted dependency to `tomg: ^0.2.0`, add CHANGELOG entries for widened ranges, verified lower bounds, obfuscated keys, and external sources, and verify `dart pub -C tomgen publish --dry-run` completes without warnings from a clean release candidate.
- [x] 6.4 Update `PUBLISHING.md` for the coordinated 0.2.0 release and run its complete default and lowest-bounds gate sequences, verifying analysis, all tests, deterministic generation, and both archive dry runs are green.
- [ ] 6.5 After explicit user confirmation, publish `tomg` 0.2.0 first and `tomgen` 0.2.0 second; verify pub.dev resolves both published versions.
- [ ] 6.6 From `appbuilder-clients/clients/webapp0`, use FVM to run `flutter pub add --dry-run tomg:^0.2.0 dev:tomgen:^0.2.0`; verify dependency resolution succeeds without overrides, then report the pending downstream OpenSpec edits without implementing them here.

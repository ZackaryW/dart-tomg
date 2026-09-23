# Tasks

## 1. CLI and Configuration Foundation

- [x] 1.1 Declare the `tomgen` executable and its direct CLI, path, YAML, formatting, and hashing dependencies; add a command entry point with `generate`, `build`, `clean`, and help handling, and verify focused command-parser tests pass.
- [x] 1.2 Implement nearest-`pubspec.yaml` package-root discovery and package-name loading, and verify tests cover root invocation, nested-directory invocation, and missing or malformed pubspec errors.
- [x] 1.3 Parse the closed `g.toml` version-1 schema into typed configuration objects, validate identifiers and defaults/enums, and verify tests cover valid multi-target input plus unsupported versions, unknown keys, missing keys, and duplicate or malformed declarations.
- [x] 1.4 Normalize and canonicalize source/output paths with package and `lib/` containment checks, including symlink escapes, and verify path-safety tests preserve every outside file.

## 2. TOML Schema Model

- [x] 2.1 Extract reserved `__tomg` metadata parsing into a shared domain parser used by the builder and CLI, and verify all existing generator metadata tests plus new parser unit tests pass unchanged.
- [x] 2.2 Implement union-of-rows scalar inference, numeric widening, presence tracking, nullable fields, and compatible manifest defaults, and verify table-driven tests cover required, optional, defaulted, and conflicting fields.
- [x] 2.3 Implement one-dimensional list inference across rows, including numeric widening and empty-list handling, and verify tests cover homogeneous lists, mixed shapes, nested lists, and missing element evidence.
- [x] 2.4 Apply explicit scalar and list enum declarations, validate names/members/literals/defaults, and verify tests cover enum keys, environment-reference placeholders, invalid members, and conflicting reused enum names.
- [x] 2.5 Reject empty registries, unknown key fields, unsupported TOML values, and invalid obfuscation targets with target/table/field context, and verify diagnostic tests assert the contextual errors and no prepared output.

## 3. Model Emission and Ownership

- [x] 3.1 Emit and format complete model libraries with annotations, parts, const constructors, fields, enums, registry aliases, and package-root asset URIs, and verify golden tests cover the endpoint and service-plan schemas.
- [x] 3.2 Emit matching `@Obfus`, `Obfuscated<ModelDeobf>`, and `deobf` members from TOML metadata, and verify a golden test contains the complete phase-one contract while containing no registry row values.
- [x] 3.3 Implement the versioned `.dart_tool/tomgen/manifest.json` with generated notices and SHA-256 ownership checks, and verify tests reject handwritten, differing untracked, and edited destinations while accepting unchanged owned files and identical checked-in generated files.
- [x] 3.4 Implement locked, manifest-last multi-file commits with same-directory temporary files, stale owned-file cleanup, unchanged-file preservation, and recoverable backups, and verify failure-injection tests leave the prior outputs and manifest intact.
- [x] 3.5 Implement `clean` for unchanged phase-one files only, and verify tests preserve edited/unowned files and build_runner-owned `.g.dart` files while removing verified model files and their ownership records.

## 4. Command Orchestration

- [x] 4.1 Wire `generate` through manifest loading, all-target parsing, inference, emission, and one ownership transaction, and verify a temporary-package integration test generates multiple models from a nested working directory.
- [x] 4.2 Wire `build` to run generation first and then `dart run build_runner build` from the package root with forwarded post-`--` arguments and inherited I/O, and verify injected-process tests cover ordering, argument forwarding, phase-one blocking, and child exit-code propagation.
- [x] 4.3 Add user-facing diagnostics and stable success summaries for all commands, and verify executable tests cover help, unknown commands, missing `g.toml`, ownership conflicts, and successful generate/clean output.

## 5. Example and Documentation

- [x] 5.1 Add `example/g.toml`, migrate its hand-written endpoint and service-plan models to `lib/generated/`, and update imports while retaining external `config/**` build inputs; verify `dart run tomgen generate` recreates the checked-in model libraries.
- [x] 5.2 Run the two-phase example build and update generated parts and integration assertions, then verify `dart run tomgen build -- --delete-conflicting-outputs` and `dart test` pass from `example/` and obfuscated plaintext is absent from generated source.
- [x] 5.3 Document the manifest schema, inference rules, external-source `build.yaml` requirement, all three commands, ownership behavior, limits, and model-first compatibility in the root and `tomgen` READMEs; verify every documented example matches the example package.
- [x] 5.4 Update package changelogs and publishing metadata for the new executable and direct dependencies, and verify `dart pub publish --dry-run` succeeds from `tomgen/` without including transient ownership or recovery files.

## 6. Repository Verification

- [x] 6.1 Format changed Dart files and run `dart analyze`, `dart test tomg`, and `dart test tomgen`; verify every command exits successfully.
- [x] 6.2 Delete only reproducible example outputs, regenerate them through `tomgen build`, and rerun `dart test example` to verify the documented clean-package workflow succeeds end to end.
- [x] 6.3 Run `openspec validate add-toml-first-generation-cli --strict` and verify the completed implementation remains consistent with all proposal, design, spec, and task artifacts.

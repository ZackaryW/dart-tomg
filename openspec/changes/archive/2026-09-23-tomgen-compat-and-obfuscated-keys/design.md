# Design

## Context

- `tomgen` 0.1.0 declares analyzer 14-era dependency bounds even though the
  current implementation passes on analyzer 10.0.1, source_gen 4.2.3,
  dart_style 3.1.7, and test 1.31.0. The 2026-09-23 probe passed 97 generator
  tests, 3 isolated-consumer tests, and 9 example tests with byte-identical
  generated output.
- Obfuscated registry keys already render as ciphertext because the registry
  key uses the same rendered field literal as the constructed value. This is
  existing behavior without a specification, focused tests, or documentation.
- TOML-first sources are currently confined to the Dart package. Phase one
  emits an `asset:` URI, and phase two reads exclusively through `BuildStep`,
  which cannot expose a file outside the package build graph.
- The first consumer keeps shared configuration at its pub workspace root,
  outside `clients/webapp0`, and requires normal `build_runner` operation from
  a fresh clone without copying or mirroring those files.

## Goals / Non-Goals

**Goals:**

- Support the verified analyzer 10.0.1 through 14.x generator stacks and keep
  the declared lower bounds continuously tested.
- Make obfuscated scalar registry keys a documented, tested contract.
- Allow TOML-first sources outside a package but inside its nearest enclosing
  pub workspace, with lexical and canonical containment enforcement.
- Make the phase-one model a deterministic, digest-pinned handoff that lets
  phase two read committed external TOML safely from a fresh clone.
- Preserve byte-identical package-local generation and all 0.1.x model-first
  annotation call sites.

**Non-Goals:**

- Supporting analyzer below 10.0.1 or analyzer 15 and later.
- Generating lookup helpers for obfuscated keys; consumers use `TomgCodec`.
- Treating reversible obfuscation as secret storage.
- Allowing arbitrary absolute paths or sources outside the enclosing pub
  workspace.
- Copying or mirroring external TOML into the package or bundling it as a
  runtime asset.
- Making raw `build_runner watch` observe edits to files outside its asset
  graph. After editing external TOML, users run `tomgen build` so phase one
  refreshes the digest before phase two.
- Implementing the downstream appbuilder-clients registry migration here.

## Decisions

1. **Generator dependency ranges use the probed endpoints.**
   - `analyzer: '>=10.0.1 <15.0.0'`
   - `source_gen: '>=4.2.3 <5.0.0'`
   - `dart_style: '>=3.1.7 <4.0.0'`
   - `build: ^4.0.0` remains unchanged.

   These are the exact lower versions exercised by the probe. Bounding at an
   untested analyzer 10.0.0 was rejected. No generator source compatibility
   shim is planned because both endpoints use the current API successfully.

2. **A separate lowest-bounds job proves the public ranges.** The Dart 3.12.2
   job writes a temporary root `pubspec_overrides.yaml` pinning analyzer
   10.0.1, source_gen 4.2.3, dart_style 3.1.7, and test 1.31.0. It runs workspace
   resolution and analysis, the tomgen and isolated-consumer tests, example
   generation and tests, and a generated-output diff. The override is ignored
   by Git and removed with the job workspace. `dart pub downgrade` was rejected
   because it also changes unrelated dependencies and does not prove the
   intended stack precisely.

3. **Obfuscated keys keep the existing rendering path.** The encoded field
   literal is both the map key and constructor value. Duplicate detection may
   compare canonical plaintext because deterministic encoding preserves
   equality. Lookup uses the matching public `TomgCodec.encodeString`,
   `encodeInt`, or `encodeDouble`, and decoded access remains available through
   the generated companion. Dedicated model-first and TOML-first tests make
   this accidental behavior contractual without adding public lookup APIs.

4. **The nearest enclosing pub workspace is the external-source boundary.**
   Phase one first discovers the package root, then walks ancestors for the
   nearest `pubspec.yaml` with a `workspace:` declaration containing that
   package. A source may escape the package only when its normalized and
   canonical paths remain inside that workspace root. Both lexical `..` escapes
   and symlink escapes are rejected. If no enclosing workspace exists, the
   package root remains the boundary. An unrestricted relative-filesystem
   boundary was rejected because it would make manifests machine-dependent and
   permit configuration reads unrelated to the project.

5. **A digest marks the generated external-source handoff.** `TomgRegistry`
   gains an optional `String? digest` named parameter. For an external source,
   phase one emits its normalized package-root-relative path and
   `digest: 'sha256:<lowercase hex>'`, calculated from the exact source bytes.
   Digest presence tells phase two that the generated source path is relative
   to the package root rather than the annotated library. Package-local targets
   retain their existing `asset:` URI and omit the digest, keeping generated
   output byte-identical. A new URI scheme and temporary-copy designs were
   rejected as unnecessary public syntax and fragile extra state respectively.

6. **Phase two verifies before parsing an external file.** For a digest-bearing
   annotation, the generator determines and verifies the input package root
   against `buildStep.inputId.package`, resolves the package-relative source,
   re-applies workspace lexical and symlink containment, reads the file directly,
   and compares its SHA-256 before parsing. A missing file, invalid digest,
   containment failure, or mismatch fails with an actionable message that the
   generated model is stale and `dart run tomgen build` must be rerun. An
   external path without a digest remains an error. Annotation sources without
   a digest retain the existing `buildStep.canRead` and `readAsString` path.

7. **Checked-in generated models make fresh-clone builds reproducible.** The
   external TOML and phase-one Dart model are both committed. A plain
   `build_runner build` can therefore verify the digest and create the `.g.dart`
   part without rerunning phase one. Editing only the TOML intentionally makes
   the model stale; `tomgen build` refreshes the model digest before invoking
   build_runner. A digest-only model change is an ordinary content update under
   the existing ownership manifest and atomic write rules.

8. **Both packages release as 0.2.0.** `tomg` adds the optional annotation
   parameter, and `tomgen` consumes it, so `tomg` is published first and
   `tomgen` declares `tomg: ^0.2.0`. An intermediate tomgen 0.1.1 was rejected
   in favor of one coherent release that the downstream consumer can adopt.

## Risks / Trade-offs

- **Intermediate analyzer versions are not directly tested.** Only the lowest
  and default endpoints run in CI. The lower-bound job catches use of newer
  APIs, while the default job covers the newest supported stack.
- **External files are invisible to the build-runner asset graph.** A raw watch
  cannot initiate work from an external edit. Documentation requires
  `tomgen build` after editing, and digest verification prevents a triggered
  phase-two build from silently consuming stale input.
- **Direct filesystem reads depend on locating the correct input package.** The
  generator verifies the discovered package identity and boundary before every
  external read and fails rather than falling back to an unverified directory.
- **Symlink topology can change between phases.** Both phases canonicalize and
  enforce the workspace boundary; a changed or escaping link is rejected.
- **Obfuscated keys are unreadable in map dumps.** This is intended; callers
  encode lookup candidates and use the decoded companion when plaintext is
  needed.

## Migration Plan

1. Add the compatible optional digest API and external-source behavior, then
   run all package-local and external-source tests before changing versions.
2. Bump `tomg` and `tomgen` to 0.2.0, set tomgen's hosted runtime dependency to
   `tomg: ^0.2.0`, and complete the default and lowest-bounds release gates.
3. After explicit user confirmation, publish `tomg` first, wait for pub.dev
   resolution, then publish `tomgen`.
4. Verify the published pair resolves in appbuilder-clients/webapp0 using its
   FVM-pinned Flutter SDK. Update the downstream OpenSpec change separately.

Before publication, rollback is a normal source revert. After publication,
published versions remain immutable; any defect is corrected in a subsequent
compatible release rather than attempting to replace 0.2.0.

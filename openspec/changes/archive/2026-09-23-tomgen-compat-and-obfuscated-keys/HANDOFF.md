# Handoff: tomg/tomgen for appbuilder-clients webapp0

Written 2026-09-23 for the agent taking over the dart-tomg work. You are
picking up planning that was done interactively with the user. Everything
under **Settled decisions** has already been decided with the user. Don't
reopen those decisions; ask only the questions under **Open questions**.

## Goal

webapp0 (`/Users/zackarywang/Documents/GitHub/appbuilder-clients/clients/webapp0`)
hardcodes its tenant allowlist and its support-center URLs in Dart. The
target is to move both into TOML compiled by our own published packages
`tomg` (runtime) and `tomgen` (CLI and build_runner generator), with the
sensitive values obfuscated in the bundle. Three things in dart-tomg block
that:

1. **Analyzer compatibility.** tomgen 0.1.0 can't be added to the
   appbuilder-clients workspace; version solving fails.
2. **Obfuscated registry keys.** The tenant access code is the registry key
   and must be obfuscated. This works today by accident and has no spec or
   tests.
3. **External TOML sources.** The user wants the TOML files at the
   appbuilder-clients workspace root (`appbuilder-clients/config/`), outside
   the webapp0 package. tomgen currently rejects that in both phases.

Items 1 and 2 are fully planned in this OpenSpec change. Item 3 is agreed in
principle but **not yet in the change artifacts**; adding it is your first
planning step.

## Settled decisions

- **freezed 4 is out.** A known SDK bug blocks it (recorded in zmem). Don't
  propose upgrading freezed or any other consumer dependency. The fix is to
  widen tomgen.
- **Analyzer range.** `analyzer >=10.0.1 <15.0.0`,
  `source_gen >=4.2.3 <5.0.0`, `dart_style >=3.1.7 <4.0.0`. `build ^4.0.0`
  is unchanged.
- **What gets obfuscated in webapp0:** tenant `code` (the registry key),
  tenant `baseUrl`, and the support `url` values.
- **Values are TOML literals only.** No `$VAR` environment references in the
  registry sources and no per-deployment profiles. Changing a value means
  editing the TOML, running `tomgen build`, and committing.
- **External sources use digest pinning ("option A").** Temp-copy and
  mirrored-copy approaches were considered and rejected, because they break
  plain `build_runner build`, `build_runner watch` and fresh clones (see the
  reasoning below).
- **Two OpenSpec changes, one per repo.** This one in dart-tomg, and
  `adopt-tomg-registries` in appbuilder-clients, which consumes the release.

## Current state

**dart-tomg** (this repo, branch `main` @ `ef45889`; the change folder is
untracked):
- `openspec/changes/tomgen-compat-and-obfuscated-keys/` contains
  `proposal.md`, `specs/field-obfuscation/spec.md`,
  `specs/release-readiness/spec.md`, `design.md` and `tasks.md`.
- `openspec validate tomgen-compat-and-obfuscated-keys --strict` passes.
- It covers items 1 and 2 and plans a **0.1.1** release of tomgen only.
  Item 3 changes that to **0.2.0 for both packages**, because `tomg` gains
  an annotation parameter.

**appbuilder-clients**:
- `openspec/changes/adopt-tomg-registries/` is valid under the `overspec`
  schema.
- It currently assumes the TOML lives **inside** webapp0
  (`clients/webapp0/config/*.toml`) and depends on tomgen `^0.1.1`. It needs
  updating once item 3 lands (see Downstream).
- Don't implement it as part of this handoff.

## Verified evidence (2026-09-23)

- **tomgen 0.1.0 against the workspace fails to resolve.** Command, from
  `appbuilder-clients/clients/webapp0`:
  `fvm flutter pub add --dry-run tomg:^0.1.0 dev:tomgen:^0.1.0`. The
  workspace locks analyzer 10.0.1, source_gen 4.2.3, build 4.0.7,
  dart_style 3.1.7 and test 1.31.0. `freezed ^3` holds analyzer below 11,
  and the `test` range allowed by Flutter's pinned `test_api` holds it
  below 14.
- **`tomg:^0.1.0` alone resolves fine.** It has no dependencies.
- **The lowest-bounds probe passes.** On a scratch copy of dart-tomg with a
  root `pubspec_overrides.yaml` pinning `analyzer: 10.0.1`,
  `source_gen: 4.2.3`, `dart_style: 3.1.7` and `test: 1.31.0`:
  - `dart analyze tomgen` reports no issues.
  - `dart test tomgen`: 97 passed.
  - `dart test ci_test`: 3 passed.
  - The example's `tomgen build` succeeds and its 9 tests pass.
  - The example's generated output is byte-identical to the committed files.
  - **No source changes are needed.** Without the `test` pin, `test_core`
    0.6.20 fails to compile against analyzer 10 (`NamedArgument` isn't a
    type).
- **The obfuscated-key probe passes.** Setting `obfuscate = ["url", "id"]`
  in the example's `config/api_endpoints.toml` makes phase one emit
  `@Obfus` on `id`. Every map key and `id` value is ciphertext, and no
  plaintext key appears in the `.g.dart`. Lookup works through the public,
  deterministic `TomgCodec.encodeString`.

## Work

### Part 1: analyzer widening (already planned; tasks.md §1, §2, §4)

Follow `tasks.md`. The lowest-bounds CI job must pin `test: 1.31.0` next to
the three generator packages, and `pubspec_overrides.yaml` must be
gitignored.

### Part 2: obfuscated registry keys (already planned; tasks.md §3)

Follow `tasks.md`. The ADDED requirement is in
`specs/field-obfuscation/spec.md`.

### Part 3: external TOML sources (not yet planned; add it to this change first)

Use the `openspec-update-change` skill to fold this into the proposal,
specs, design and tasks. Keep the three parts coherent, and change the
release plan to tomg and tomgen **0.2.0**.

**Behavior agreed with the user:**
1. Phase one (the CLI) accepts a `g.toml` `source` that escapes the package,
   such as `../../config/tenants.toml`, provided it resolves inside the
   boundary (see Open questions; the recommended boundary is the enclosing
   pub workspace root). Lexical and symlink escapes beyond the boundary
   stay rejected. Outside a pub workspace, the current package-only rule
   still applies.
2. For an external source, phase one writes the SHA-256 of the TOML
   content into the generated annotation, for example
   `@TomgRegistry(<source>, key: 'code', digest: 'sha256:<hex>')`. This
   needs a new optional `digest` named parameter on `TomgRegistry` in
   `tomg`. It must be additive and must not break 0.1.x model-first users.
3. Phase two cannot serve files outside the package through build_runner.
   When the annotation carries a digest and the source is external, the
   generator reads the file directly from disk, checks the digest, and
   fails with an actionable "stale, run `tomgen build`" error on a
   mismatch. Package-local sources keep today's
   `buildStep.canRead`/`readAsString` path unchanged. Without a digest, an
   external source is still an error.
4. **Why this works:** build_runner never tracks the external file, but it
   does track the generated model library. The digest in that library
   changes whenever the TOML changes and phase one reruns. Plain
   `build_runner build`, `watch` and fresh clones all still work, because
   the real TOML is committed and readable.

**Code touchpoints:**
- `tomgen/lib/src/cli/project.dart:61-87`: `resolveContainedPath`, the
  containment check. It takes a `requireDescendant` flag and rejects both
  lexical and symlink escapes.
- `tomgen/lib/src/cli/config.dart` around line 135 (`requireDescendant: true`)
  and lines 179-272, where targets are built (`sourceRelative`,
  `sourceFile`).
- `tomgen/lib/src/cli/emitter.dart:48` emits
  `@TomgRegistry('asset:$packageName/$source', key: ...)`. An `asset:` URI
  can't represent a path outside the package, so you need to choose an
  encoding for external sources, such as a package-root-relative
  `../../config/x.toml` plus `digest:`. Record the choice in design.md.
- `tomgen/lib/src/tomg_generator.dart:44-61`: the source is resolved with
  `AssetId.resolve(Uri.parse(source), from: buildStep.inputId)` and read
  through `buildStep`. For external reads you also need the package root
  directory. build_runner runs with the package root as the working
  directory; verify that against `buildStep.inputId.package` and don't
  assume it.
- `tomg/lib/src/annotations.dart:11`:
  `const TomgRegistry(this.source, {required this.key})`. Add
  `this.digest`.
- `tomgen/lib/src/cli/ownership.dart`: the phase-one manifest and hashes.
  Confirm that a digest change counts as a normal content change of the
  owned file.

**Tests to add, at minimum:**
- An external source inside the workspace generates.
- An external source outside the workspace is rejected.
- A symlink escape is rejected.
- An edited TOML without a phase-one rerun fails phase two with the stale
  error.
- A fresh-clone-style plain `build_runner build` succeeds with no phase-one
  rerun.
- Existing package-local targets produce byte-identical output with no
  digest emitted.
- A `ci_test` consumer inside a temporary pub workspace, with the TOML at
  the workspace root.

**Docs:** the README gets an external-sources section (the boundary, the
digest, and "always run `tomgen build` after editing"). PUBLISHING.md gets
the 0.2.0 release, published tomg first.

## Downstream (appbuilder-clients, after 0.2.0 ships; not part of this handoff)

`adopt-tomg-registries` will need the following updates:
- Change the TOML paths to `appbuilder-clients/config/tenants.toml` and
  `config/support_links.toml`, with `clients/webapp0/g.toml` sources
  written as `../../config/...`.
- Drop the webapp0 `build.yaml` `sources:` task (2.2), which is no longer
  needed.
- Depend on `tomg`/`tomgen` `^0.2.0`.
- Update the paths in the design's value table (Decision 7) and in the
  spec text ("under `clients/webapp0/config/`").

Tell the user these edits are pending rather than making them silently.

## Environment gotchas

- **appbuilder-clients must use FVM.** It pins Flutter 3.47.5 (Dart
  3.13.4) in `.fvmrc`. The `flutter` on PATH is 3.44.2 and gives misleading
  resolution errors (a `meta` pin). Always use `fvm flutter` / `fvm dart`
  there.
- **dart-tomg uses the system Dart**, 3.12.2, which matches the minimum
  SDK.
- **Commits use the zmem commit grammar.** Use the `zmem-commit` /
  `zmem-author-commits` skills. Don't pipe `check-commit-msg` through
  `jq`, because the pipe hides its exit code.
- **Publishing is irreversible.** Confirm with the user before
  `dart pub publish`, and publish tomg before tomgen.
- **Probe on scratch copies**, as the evidence above was produced, for
  example `git archive HEAD | tar -x -C <scratch>`. Don't add
  `pubspec_overrides.yaml` to the real repo.
- **mem0-mcp needs authorization** in an interactive session. zmem is
  available.

## Open questions for the user

1. **Boundary for external sources.** The recommendation is the enclosing
   pub workspace root (the nearest ancestor `pubspec.yaml` with a
   `workspace:` key). The user hasn't explicitly confirmed this over
   "anywhere relative".
2. **Release versions.** The plan is 0.2.0 for both packages. Confirm the
   user doesn't want tomgen 0.1.1 (items 1 and 2) shipped first, so that
   webapp0 can start before item 3 is done.

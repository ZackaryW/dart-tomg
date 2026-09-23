# Design

## Context

`tomgen` is currently a `source_gen` builder. It begins with an annotated,
hand-written model library and emits the registry and optional decoded companion
into that library's `.g.dart` part. TOML may live outside `lib/` when the package
adds it to build_runner's source graph. The example already uses this mechanism
for `config/**` and demonstrates the field types the first CLI version can infer.

The requested workflow adds a phase before this builder. That phase runs as a
normal Dart executable, reads package files directly, and creates the annotated
model libraries that the existing builder consumes. See `proposal.md` for the
motivation and `specs/toml-first-generation/spec.md` for observable behavior.

## Goals / Non-Goals

**Goals:**

- Keep one implementation of registry construction, environment substitution,
  constant rendering, and obfuscation encoding in the existing builder.
- Make phase-one output deterministic, reviewable, and safe to regenerate.
- Give configuration and inference errors stable target, table, and field
  context before build_runner starts.
- Keep the CLI usable from any directory within a single Dart package.

**Non-Goals:**

- Generating nested model declarations, arrays of tables, nested lists, maps,
  sets, records, or TOML date/time models.
- Coordinating build_runner watch mode with phase-one file watching.
- Editing a consumer's `pubspec.yaml` or `build.yaml`; sources outside default
  build_runner roots still need to be included in the package build graph.
- Treating generated model files as an API schema migration system.

## Decisions

### Add a package executable and keep the existing builder as phase two

Declare `tomgen` in `executables` and add `bin/tomgen.dart`. The executable
locates the package root, parses `g.toml`, prepares every model file, commits the
phase-one transaction, and optionally starts build_runner. `build` launches
`Platform.resolvedExecutable` with `run build_runner build`, a working directory
of the discovered package root, direct process I/O, and arguments supplied after
`--`.

This preserves the analyzer-backed validation and output already covered by the
`toml-codegen` and `field-obfuscation` specs. A build_runner builder that creates
another primary Dart input would need output-extension remapping and builder
ordering in every consumer, while still making project-level configuration and
safe stale cleanup awkward. Reimplementing `.g.dart` generation in the CLI
would duplicate the current generator.

### Use one strict, versioned root manifest

The first schema is:

```toml
version = 1
output = "lib/generated"

[targets.api_endpoints]
source = "config/api_endpoints.toml"
model = "ApiEndpoint"
key = "id"

[targets.api_endpoints.defaults]
visible = true
enabled = true

[targets.service_plans]
source = "config/service_plans.toml"
model = "ServicePlan"
key = "tier"

[targets.service_plans.enums.tier]
name = "PlanTier"
values = ["starter", "enterprise"]

[targets.service_plans.enums.transports]
name = "Transport"
values = ["https", "grpc"]
```

Top-level and target keys are closed sets. Target names are lower snake case and
produce `<output>/<target>.dart`. Registry aliases derive from the model as
`<lowerCamelModel>Registry`. This keeps the common manifest short while version
checking leaves room for later schema changes. Per-target arbitrary Dart source
snippets and configurable symbol templates were rejected because they would
weaken validation and make generated output difficult to predict.

### Parse package identity and TOML into domain objects before writing

Read the package name from the root `pubspec.yaml`, then parse and validate every
manifest target and source into immutable configuration and schema objects. A
small shared registry-document parser should remove and validate `__tomg`
metadata for both the CLI and `TomgGenerator`; each caller translates domain
errors into its own CLI or `InvalidGenerationSourceError` presentation.

Separating parsing, inference, emission, orchestration, and filesystem commit
makes the core behavior testable without subprocesses. Duplicating metadata
parsing inside the CLI was rejected because the two phases could then disagree
about reserved metadata before the exact-match guard runs.

### Infer from the union of rows with explicit enum intent

The inference pass records every occurrence of each field across all registry
rows. Scalar observations must agree, except `int` plus `double` widens to
`double`. Lists combine item evidence across rows and reject nested or mixed
shapes. Presence in all rows creates a required parameter; partial presence
creates a nullable optional parameter unless a compatible manifest default is
present.

String data does not imply an enum. The `enums` declaration supplies the Dart
type name and complete allowed member set for a scalar string or string-list
field. This avoids unstable enums whose API changes just because a data row is
added. Environment-reference strings remain strings during phase one; an enum
declaration can establish enum intent, while phase two resolves the environment
and performs the final value conversion. An environment-only numeric or boolean
field therefore needs literal/default type evidence in this version or remains
a string field.

Implicit enums and inference from the first row were rejected because both make
model APIs depend on incidental data order. General type override syntax is
deferred until a concrete case requires it.

### Emit complete source_gen input libraries

For each target, emit a generated notice, `package:tomg/tomg.dart` import,
`part '<target>.g.dart'`, declared enums, the model, and the registry alias. The
annotation source is `asset:<pubspec-name>/<normalized-source>` so data may stay
under a root `config/` directory. Consumers must include such directories in
their build_runner target sources, as the existing example does.

Valid `__tomg.obfuscate` metadata places `@Obfus()` on both the field and its
constructor parameter, adds `implements Obfuscated<ModelDeobf>`, and emits the
`deobf` getter. Phase two then generates `ModelDeobf` and verifies the TOML and
Dart declarations match. Phase one rejects unsupported targets first so it never
deliberately creates a contract the builder will reject.

Use `dart_style` to format the in-memory source before any filesystem commit.
Generating model source without formatting was rejected because the files are
expected to be checked, reviewed, and often committed.

### Commit all model outputs as one ownership-checked transaction

Store a versioned JSON manifest at `.dart_tool/tomgen/manifest.json`, with each
owned package-relative path and SHA-256 content hash. A path is writable or
deletable only when it is present in the prior manifest, contains the exact
generated notice, and its current hash matches the recorded hash. A path not in
the manifest may be adopted without rewriting only when it contains the notice
and is byte-for-byte identical to the newly generated content. This lets a fresh
clone establish local ownership for checked-in generated models without trusting
the notice alone for a content change.

Prepare and format every new file, validate all paths and prior ownership, and
write temporary siblings before renaming any output. Commit replacements,
additions, stale deletions, and the new manifest only after all preparation
succeeds. Preserve unchanged files without rewriting them. If a commit-level I/O
operation fails, report the affected path and retain temporary recovery data;
the implementation should use backups during the short rename sequence so it
can restore the prior transaction where the platform permits.

A header alone was rejected as proof of ownership because copied or manually
created files could be deleted. A manifest alone was rejected because a stale or
tampered manifest could claim a handwritten path. Hash checks also turn edits to
generated files into a visible conflict instead of silently discarding them.

### Keep clean limited to phase-one ownership

`tomgen clean` validates the same notice and recorded hashes, deletes only
verified phase-one model libraries, and removes the ownership manifest when all
owned files are gone. It reports and preserves edited files. build_runner owns
`.g.dart` and its cache, so users retain `dart run build_runner clean` for those
artifacts.

Combining both clean operations was rejected because it would make a command
described by tomgen's ownership manifest remove outputs owned by other builders.

## Risks / Trade-offs

- [A TOML value change alters an inferred public field type] → Document generated
  models as data-derived API, validate all rows together, and require explicit
  enum declarations; future manifest versions can add general type pins.
- [An external source is valid for phase one but absent from build_runner's asset
  graph] → Preserve phase-one output, propagate the builder failure, and show the
  required `build.yaml` source configuration in setup and the example.
- [Two concurrent CLI processes race on the ownership manifest] → Acquire an
  exclusive lock beneath `.dart_tool/tomgen/` for generate, build phase one, and
  clean, then release it before the long-running build_runner child begins.
- [A process terminates during rename commit] → Use same-directory temporary
  files, short-lived backups, and manifest-last commit ordering; detect leftover
  recovery files on the next run and report or restore them deterministically.
- [The active nested-object change expands phase-two types before this CLI can
  infer them] → Continue rejecting object-shaped data in phase one; nested model
  generation gets its own manifest and inference contract later.
- [Formatter or analyzer SDK constraints enlarge the dev tool dependency set] →
  add direct CLI dependencies with SDK-compatible bounds and validate publish
  dry runs for `tomgen`.

## Migration Plan

Ship the CLI as an additive `tomgen` feature. Convert the example by adding a
root `g.toml`, generating its model libraries under `lib/generated/`, updating
imports, and retaining `config/**` in `build.yaml`. Keep the existing
hand-written examples in documentation as the model-first path and add the CLI
path beside them.

Rollback removes `g.toml` and its manifest-owned model files and restores or
keeps hand-written annotated models; the builder and `tomg` runtime require no
rollback migration.

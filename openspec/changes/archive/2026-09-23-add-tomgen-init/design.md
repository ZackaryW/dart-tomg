# Design

## Context

See `proposal.md` for motivation and the specification delta for observable
behavior. The current executable has a small command parser and dispatcher in
`tomgen/lib/src/cli/app.dart`. Package discovery and contained-path validation
already live in `project.dart`, while `config.dart` is the authoritative parser
for version-1 `g.toml` files. Generation already uses a preflight-and-commit
workflow to avoid overwriting unowned output.

Initialization touches three independent user-owned inputs: `g.toml`, an
optional starter TOML file, and `build.yaml`. It must work from a package
subdirectory, must not turn external TOML into a Flutter asset, and must not
partially scaffold a package if any input is invalid or conflicts. Existing
`build.yaml` files can contain comments and unrelated builder configuration, so
serializing a parsed YAML map would be destructive.

## Goals / Non-Goals

**Goals:**

- Give the CLI one typed initialization request that can represent starter and
  existing-source modes without ambiguous combinations.
- Reuse the current project, manifest, identifier, and path rules so an
  initialized project is accepted by generation immediately.
- Compute and validate every filesystem change before committing any of them.
- Preserve compatible user-authored `build.yaml` text while adding the narrowest
  source entry required by build_runner.
- Make an identical second invocation a successful no-op with useful output.

**Non-Goals:**

- Running `pub add`, resolving packages, generating models, or invoking
  build_runner from `init`.
- Merging a new target into an existing nonmatching `g.toml` in the first
  version.
- Adding interactive prompts, `--force`, or an initializer-specific lock file.
- Inferring nested model overrides, enums, defaults, or obfuscated fields during
  initialization.

## Decisions

### 1. Use an explicit custom-target option set

The command syntax will be:

```text
tomgen init
tomgen init --source <path> --target <name> --model <name> --key <field>
            [--output <path>]
```

Zero options select the starter request (`config/items.toml`, target `items`,
model `Item`, key `id`, output `lib/generated`). Specifying any custom-target
option requires `--source`, `--target`, `--model`, and `--key`; `--output`
defaults to `lib/generated`. The parser rejects positional arguments,
duplicates, unknown options, build argument forwarding, and partial option
sets. `TomgenInvocation` will carry a command-specific immutable init request
instead of overloading the build-only forwarded-argument list.

This keeps the command deterministic for CI and avoids positional argument
ordering that would be hard to remember. An interactive wizard was considered,
but it would be harder to test, automate, and rerun idempotently.

### 2. Plan initialization from existing validators

A `TomgenInitializer` service will discover the nearest package with
`TomgenProject.discover`, normalize all requested paths, and construct the exact
bytes proposed for each affected file. Shared identifier and target validation
will be extracted from `config.dart` where necessary so initialization and
manifest loading cannot drift. The completed candidate manifest will be parsed
through `TomgenConfig.load` against the proposed source before it is eligible
for commit; a filesystem abstraction or temporary validation root may be used
so validation itself does not create package directories.

For existing-source mode, `--source` must name an existing regular `.toml` file
within the package. The initializer parses it and verifies that at least one
record supplies the requested key and that the current inference pipeline can
derive a model. Starter mode proposes a small array-of-tables document with one
`id` row, sufficient for the existing generator to infer `Item`.

Building the manifest with the same constraints as the loader is preferred to
maintaining a looser initializer schema that could emit an unusable project.

### 3. Validate dependencies without editing `pubspec.yaml`

The initializer parses `pubspec.yaml` and requires `tomg` in `dependencies`,
plus `tomgen` and `build_runner` in `dev_dependencies`. Workspace, hosted, git,
and path specifications all count when they appear in the correct section.
Missing or misplaced entries produce exact commands such as
`dart pub add tomg` and `dart pub add --dev tomgen build_runner`; no package
manager process runs automatically.

Automatic dependency edits were considered, but they introduce network access,
solver side effects, lockfile mutations, and SDK-specific workspace behavior
into a command whose file transaction otherwise remains local and predictable.

### 4. Add only the required build input with structure-preserving YAML edits

An absent `build.yaml` receives a minimal `$default` target whose `sources`
sequence includes standard package inputs and the exact external source path.
If `build.yaml` exists, it is parsed for semantic validation and edited with a
structure-preserving YAML editor. The initializer accepts a `$default.sources`
list that already covers the source, or appends the exact package-relative path
when the list has a supported sequence shape. Other targets, builders, source
entries, key ordering, whitespace, and comments remain untouched.

Unsupported aliases, scalar/map source shapes, duplicate structural keys, or
other states where a safe local edit cannot be proven are conflicts. The error
describes the manual `sources` entry rather than replacing the file. A full
parse-and-reserialize approach was rejected because it would erase comments and
cause unrelated formatting churn. Adding TOML to Flutter `assets` is excluded
because build_runner input visibility and runtime asset bundling solve different
problems.

### 5. Treat exact content and semantic source coverage as reusable

For `g.toml` and the starter source, an existing file is reusable only when its
bytes equal the proposed scaffold. A differing file is a conflict, including a
different but valid manifest, because merging or replacing it would change
user-authored project intent. For `build.yaml`, semantic coverage of the source
is reusable even when the text differs from the initializer's preferred form.

This narrow rule makes repeated runs safe and understandable. A `--force`
escape hatch was rejected because it would weaken the overwrite guarantees and
make recovery depend on version control.

### 6. Separate preflight from a rollback-capable commit

The initializer first returns an `InitializationPlan` containing normalized
paths, original bytes or absence markers, proposed bytes, and a created/reused
classification. Preflight collects all dependency, option, path, content, and
YAML conflicts and writes nothing. If it succeeds, commit writes proposed bytes
to temporary sibling files, verifies that destinations still match the observed
state, then renames them into place. If a later rename fails, it restores every
previous destination from the captured bytes and removes files created by this
attempt.

The result reports created and reused package-relative paths, followed by
`dart run tomgen build` and the discovered package root. `init` returns after
this result and never creates generated Dart files or the ownership manifest.

Per-file direct writes were considered simpler, but they can leave `g.toml`
behind when a later `build.yaml` update fails. Reusing the generator's ownership
manifest was also rejected because these files remain user-owned inputs.

## Risks / Trade-offs

- **[YAML syntax supported by the parser may exceed syntax safely editable by
  the structure-preserving editor]** -> Reject uncertain shapes during preflight
  and print the exact manual source entry required.
- **[A source glob can cover a path without matching a simple literal check]** ->
  use the build package's glob semantics when testing coverage and append an
  exact path only when no existing include covers it.
- **[Another process can modify a destination between preflight and commit]** ->
  compare the observed bytes immediately before each rename, abort on drift, and
  roll back changes from the current transaction.
- **[Filesystem rename guarantees vary across platforms]** -> Keep temporary
  files beside their destinations, use same-volume renames, and exercise failure
  injection in transaction tests.
- **[Strict conflicts prevent adding a target to an established manifest]** ->
  keep the first release safe and deterministic; a future additive command can
  define manifest merge semantics separately.

## Migration Plan

1. Add the parser and initializer behind the new `init` command without changing
   existing command behavior.
2. Add focused unit and integration coverage for clean, existing-source,
   idempotent, conflicting, and rollback cases.
3. Update the example and documentation to make `tomgen init` the shortest setup
   path while retaining the manual configuration reference.
4. Release as an additive minor feature. Rollback consists of reverting the CLI
   change; packages already initialized contain ordinary supported input files
   and continue to work with `tomgen build`.

# Design

## Context

See `proposal.md` for motivation. Phase one currently parses every target into a
flat inferred schema, supports scalar, enum, and scalar-list fields, and emits
one model class. Phase two independently inspects an annotated Dart constructor
and renders the same leaf types into a generated registry. TOML tables already
arrive as maps and arrays of tables arrive as lists of maps, but both phases
currently reject those shapes below the registry-row level.

The version-1 `g.toml` contract is strict and intentionally TOML-first. Users
should not need to translate configuration into handwritten Dart type metadata
or maintain a schema snapshot. Generated phase-one files are hash-owned and
committed as one transaction, so recursive inference and validation must finish
before any file changes.

## Goals / Non-Goals

**Goals:**

- Represent scalar, enum, object, scalar-list, and model-list shapes recursively
  in phase one and phase two.
- Infer every generated field type and nested model name from current TOML plus
  semantic hints, without handwritten type declarations or a lock file.
- Generate one const-capable Dart model graph per target and render nested
  registry values with full source paths in diagnostics.
- Produce deterministic results for the same current inputs regardless of row or
  map iteration order.
- Preserve existing flat generated output byte-for-byte.

**Non-Goals:**

- Maps, sets, records, tuples, nested lists, heterogeneous lists, TOML date or
  time values, polymorphic models, factories, or positional constructors.
- Persistent schema history, user-authored field types, structural model
  deduplication, automatic English singularization, or custom inferred names.
- Object-valued registry keys or obfuscation within nested object graphs.
- Runtime loading, runtime reflection, or bundling TOML as an application asset.

## Decisions

### Use recursive phase-one shapes and phase-two model descriptions

Replace the flat scalar-plus-list flag in phase one with recursive scalar, enum,
model, and list shapes. A model owns ordered constructor fields; a list owns
exactly one supported item shape. Phase two builds an equivalent recursive
description from analyzer elements. Validation and rendering walk these
recursive descriptions while sharing path and leaf-conversion behavior.

This is preferable to adding isolated map branches to the existing renderer. A
recursive contract keeps required fields, defaults, environment conversion,
paths, and supported-type checks consistent at every depth without coupling the
CLI's inferred models to analyzer elements.

### Infer a fresh complete graph on every generation

Every `generate` and `build` reads `g.toml` and all target TOML sources, then
infers the complete current graph. There is no `g.lock`, schema mode, refresh
flag, or field-type table. A structural data edit therefore changes the next
generated Dart API directly, while identical current inputs always produce
identical output.

This follows the package's TOML-first purpose. Consumers that require an API
review boundary can review and commit the generated Dart diff, which already
contains the exact public classes and fields, without introducing another
generated representation of the same schema.

### Infer object shapes by path across all occurrences

For each target, traverse every registry row and group observations by complete
field path. A map is an object observation. A list of maps is a model-list
observation; its item fields are merged across every item and row. Existing
numeric widening and presence rules apply independently inside each inferred
model. Empty lists contribute presence but no item-shape evidence.

Mixing scalar, object, scalar-list, and model-list observations at one path is a
hard error. A nested object or model-list field absent from any occurrence
becomes an optional nullable field. A child absent from any instance of its
model follows the same rule.

Inferring across all occurrences avoids first-row and iteration-order behavior.
All-empty model lists fail because no authored input establishes an item shape.

### Let semantic hints address dotted paths

Existing defaults and enum declarations remain the only schema-related author
input because they express intent that values alone cannot reliably establish.
Extend their field keys from one identifier to a validated dotted identifier
path. For a model list, the path traverses through the list item model, so
`replicas.transport` describes the `transport` field on every inferred item.

A dotted default participates in presence and leaf inference at its exact model
path. A dotted enum declaration converts a string or string-list leaf at that
path to the named enum. Unknown paths, object-valued defaults, enum declarations
on object or model-list fields, and conflicting declarations fail before output.

This preserves defaults and enum intent recursively without asking users to
write general Dart types.

### Derive names from the root model and full field path

An inferred object uses the root model followed by PascalCase path segments,
for example `ServiceDatabaseTls`. A model-list item additionally uses `Item`,
for example `ServiceReplicasItem`. Detect collisions after normalization and
report both source paths.

Path-based naming is deterministic without unreliable singularization. The
same current schema always receives the same names, and removing or moving a
path naturally changes the generated API.

### Emit all nested declarations in one owned library

The phase-one file continues to contain the annotated root model and registry
alias. It additionally emits every reachable enum and nested model in stable
child-before-parent, then lexical order, with const unnamed constructors and
final fields. Only the root model receives `@TomgRegistry` and the obfuscation
companion contract.

Keeping the graph in one library avoids import generation, preserves the
existing one-target/one-owned-file transaction, and lets the generated part
refer to all inferred types directly. Existing flat targets follow the current
emission path so their bytes remain unchanged.

### Recursively inspect hand-written const models in phase two

After scalar, enum, and `List` classification, phase two treats a concrete
non-generic interface type as a nested model candidate. It accepts only a const
unnamed constructor containing named parameters with recursively supported
types. It resolves local, unprefixed imported, and prefixed imported references
in the annotated library's context, caches completed model descriptions, and
tracks the active type stack to reject cycles.

For `List<Model>`, TOML must supply a list of maps. Rendering produces a typed
constant list of nested constant constructor expressions. Validation and error
paths include list indices before any source is returned.

Allowing arbitrary factories or positional constructors would require a mapping
language beyond field-name matching and would weaken diagnostics, so those
constructors remain unsupported.

### Keep obfuscation at root scalar leaves

Phase one rejects `__tomg.obfuscate` entries that name an object or any list.
Phase two rejects `@Obfus` on object and collection fields and on
constructor-bound fields within reachable nested models. Supporting nested
obfuscation would require nested decoded companions and a new public access
contract, which is separate from structured schema generation.

## Risks / Trade-offs

- [A TOML structure edit changes the public Dart API immediately] → Keep
  generation deterministic and make the generated Dart diff explicit in source
  control and CI.
- [An all-empty model list has no inferable type] → Fail with the exact path
  and require at least one representative item in current TOML.
- [Inferred names become long or collide at deep paths] → Use complete paths
  and reject normalized collisions with both source paths.
- [Dotted semantic hints target the wrong shape] → Validate every segment
  against the completed inferred graph before emission.
- [Recursive analyzer traversal loops or loses import prefixes] → Cache
  completed descriptions, track active type stacks, and analyze fixtures for
  local and prefixed imported types.
- [Array-of-tables diagnostics become hard to locate] → Carry one structured
  path object through validation and render dotted fields plus indices.
- [The broader change overlaps `add-nested-object-support`] → Treat this
  change as its replacement and do not apply the older task list independently.

## Migration Plan

Release this as an additive generator update. Existing flat manifests and
models retain their output. Projects can add nested tables and arrays of tables
directly to their TOML, run the existing `tomgen generate` or `tomgen build`,
and commit the resulting Dart changes. Rollback requires reverting structured
TOML and its generated models before using an older generator.

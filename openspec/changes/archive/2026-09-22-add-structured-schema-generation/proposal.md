# Proposal

## Why

Real TOML configuration commonly contains nested objects and repeated object
records, but tomgen's TOML-first workflow currently stops at flat scalar and
scalar-list models. The complete Dart model graph should be derived from TOML
without requiring users to restate types in a manifest or maintain a schema
lock artifact.

## What Changes

- Infer nested Dart model classes recursively from TOML tables and inline
  tables, and emit the entire object graph as compile-time-constant Dart.
- Support TOML arrays of tables and arrays of inline tables as `List<Model>` in
  both generated and hand-written const models.
- Derive field types, nested model names, nullability, requiredness, and list
  item shapes automatically from all current TOML rows on every generation.
- Define stable path-based nested model naming, recursive shape merging, indexed
  and dotted diagnostics, cycle rejection, and deterministic output ordering.
- Keep `g.toml` focused on targets and semantic hints such as defaults and enum
  intent; users do not write Dart field types or duplicate inferred structure.
- Do not create or consume a schema lock file; changed TOML structure directly
  produces the corresponding generated Dart API on the next generation.
- Continue rejecting object-valued registry keys, nested collections beyond
  `List<Model>`, and obfuscation on object, collection, or nested-model fields.
- Supersede the unimplemented `add-nested-object-support` plan with this broader
  contract so nested models and model collections share one implementation.

## Capabilities

### New Capabilities

- `structured-schema-generation`: Define recursive automatic TOML-first model
  inference and arrays-of-tables generation without handwritten type metadata or
  a schema lock file.

### Modified Capabilities

- `toml-codegen`: Extend constructor mapping from scalar and enum leaves to
  nested const models and one-dimensional `List<Model>` values.
- `field-obfuscation`: Define explicit rejection boundaries for object-valued,
  model-list, and nested-model obfuscation under the expanded type system.

## Impact

The change affects schema inference, Dart model emission, the analyzer-driven
registry generator, generated diagnostics, examples, READMEs, and changelogs.
It adds no runtime dependency, generated lock artifact, or `tomg` runtime API.
Existing flat targets and manifests remain source-compatible.

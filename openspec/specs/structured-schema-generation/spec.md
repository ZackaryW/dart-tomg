# structured-schema-generation Specification

## Purpose

Generate complete recursive Dart model graphs automatically from structured
TOML without requiring handwritten field types or a schema lock artifact.

## Requirements

### Requirement: Recursive TOML-first model inference

The CLI SHALL recursively infer custom Dart models from TOML tables and inline
tables. It SHALL merge field evidence across every occurrence at the same field
path, preserve the existing scalar, enum, default, nullability, and
numeric-widening rules at leaf fields, and keep the generated object graph
compile-time constant.

#### Scenario: Nested table infers a nested model

- **WHEN** registry rows supply a table at field `database` with compatible
  scalar or structured children
- **THEN** phase one generates a typed nested model for `database` and phase two
  emits a constant nested constructor expression for every present value

#### Scenario: Inline table follows the same inference rules

- **WHEN** a nested value is written as an inline TOML table
- **THEN** the CLI infers and emits the same model shape it would produce from
  the equivalent nested table syntax

#### Scenario: Nested child presence is merged across occurrences

- **WHEN** a child field is absent from at least one occurrence of its enclosing
  model and has no configured default
- **THEN** that child becomes an optional nullable constructor parameter without
  changing the presence contract of unrelated fields

#### Scenario: Conflicting nested shapes are rejected

- **WHEN** observations at one dotted field path conflict between scalar,
  object, or list shapes, or contain incompatible leaf values
- **THEN** generation fails before output with the target, registry row, and
  complete dotted field path

### Requirement: Arrays of tables generate model lists

The CLI SHALL infer a one-dimensional TOML array of tables or array of inline
tables as `List<Model>`. It SHALL merge item-field evidence across all items and
all registry rows, preserve item order, and emit a typed constant Dart list of
constant model instances.

#### Scenario: Array of tables infers List of model

- **WHEN** a field contains TOML array-of-tables entries with compatible object
  shapes
- **THEN** the generated root model declares `List<ItemModel>` and the registry
  contains a constant list of constant item-model instances in source order

#### Scenario: Array of inline tables follows the same rules

- **WHEN** a field is a TOML array whose elements are inline tables
- **THEN** it is handled identically to the equivalent TOML array of tables

#### Scenario: Empty model lists use other observed evidence

- **WHEN** some list occurrences are empty and another occurrence establishes
  the item model
- **THEN** empty occurrences generate typed empty constant lists without losing
  the inferred item type

#### Scenario: Model list has no item evidence

- **WHEN** every occurrence of an inferred model list is empty
- **THEN** inference fails with the target and field path instead of guessing a
  dynamic or placeholder type

#### Scenario: Invalid model-list item reports its index

- **WHEN** one object in a model list has an unknown, missing, or incompatible
  child value
- **THEN** generation fails with a path containing the zero-based list index and
  the nested child path

### Requirement: Deterministic generated model graph

Phase one SHALL derive unique nested model names from the configured root model
and complete field path, adding an `Item` suffix for model-list items. It SHALL
emit each reachable model exactly once in deterministic order and SHALL reject
automatic name collisions rather than silently merging unrelated object paths.

#### Scenario: Nested model name is path-derived

- **WHEN** root model `Service` contains object path `database.tls`
- **THEN** inferred nested model names include the root and path segments so the
  result is stable and independent of registry row order

#### Scenario: Model-list item name is unambiguous

- **WHEN** root model `Service` contains model-list field `replicas`
- **THEN** its inferred item model has a deterministic path-derived name ending
  in `Item`

#### Scenario: Automatic names collide

- **WHEN** different object paths normalize to the same generated model name
- **THEN** phase one rejects the inference with both paths instead of merging
  the models

#### Scenario: Existing flat target is unchanged

- **WHEN** a version-1 target contains only currently supported flat values
- **THEN** its generated Dart API and formatting remain unchanged

### Requirement: Current TOML is the complete schema source

On every generation, field types, nested model names, nullability, requiredness,
and collection shapes SHALL be derived from the current `g.toml` targets and
their TOML sources. Existing defaults and explicit enum declarations SHALL
remain semantic input where values alone cannot express author intent. The CLI
SHALL NOT require or create field-type declarations or a schema lock file.

#### Scenario: Nested types require no manifest duplication

- **WHEN** TOML contains compatible nested tables or arrays of tables
- **THEN** the user does not add Dart field types or nested model declarations
  to `g.toml` for tomgen to generate the complete model graph

#### Scenario: Structural TOML edit changes generated API

- **WHEN** current TOML adds, removes, or changes a field shape and the complete
  current input remains inferable
- **THEN** the next generation deterministically emits the corresponding updated
  Dart model graph without a separate lock refresh step

#### Scenario: No schema lock artifact is produced

- **WHEN** `tomgen generate`, `tomgen build`, or `tomgen clean` completes
- **THEN** tomgen neither reads nor writes `g.lock` or another schema snapshot

#### Scenario: Enum intent remains explicit

- **WHEN** string data should generate a Dart enum rather than `String`
- **THEN** the existing enum declaration supplies that semantic intent while all
  enclosing object and list structure remains inferred

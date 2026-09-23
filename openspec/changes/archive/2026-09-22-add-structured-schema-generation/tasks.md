# Tasks

## 1. Recursive TOML-First Inference

- [x] 1.1 Replace the flat phase-one type representation with recursive scalar, enum, object, and list shapes plus a structured dotted-and-indexed path type; verify focused unit tests construct and compare representative nested shapes
- [x] 1.2 Implement recursive observation and union across all rows, nested object occurrences, and model-list items while retaining numeric widening and presence tracking; verify nested tables, inline tables, arrays of tables, arrays of inline tables, and mixed empty/non-empty lists infer deterministically
- [x] 1.3 Derive deterministic path-based names for nested models and model-list items, detect normalized name collisions, and order the complete graph independently of TOML map iteration; verify shuffled equivalent inputs produce equal schemas and collision fixtures name both paths
- [x] 1.4 Extend defaults and enum declarations to validated dotted field paths, including traversal through model-list items; verify nested scalar and scalar-list leaves accept compatible hints while unknown, object-valued, and conflicting paths fail before output
- [x] 1.5 Add failure coverage for scalar/object/list conflicts, heterogeneous or nested lists, arrays with mixed object and scalar items, unsupported TOML types, all-empty model lists, and invalid dotted hints; verify every diagnostic includes target, table, and complete path without partial output

## 2. Recursive Model Emission

- [x] 2.1 Extend phase-one emission to write every reachable nested model with a const named-parameter constructor and final typed fields in stable child-before-parent order; verify golden tests cover two-level objects and model-list item classes
- [x] 2.2 Emit required, nullable, defaulted, `List<Model>`, nullable-model, and nullable-model-list fields correctly while keeping only the root annotated; verify generated libraries format and analyze successfully
- [x] 2.3 Preserve existing enum placement, root obfuscation contract, registry alias, generated notice, and ownership transaction for multi-model files; verify existing flat endpoint and service-plan golden output remains byte-for-byte unchanged
- [x] 2.4 Extend phase-one obfuscation validation to reject object fields and all lists; verify errors occur before ownership checks commit any model file

## 3. Recursive Registry Generation

- [x] 3.1 Add hand-written model fixtures for local, unprefixed imported, and prefixed imported nested const types, nullable/defaulted objects, two-level nesting, `List<Model>`, and empty model lists; verify their generated parts analyze and all expressions remain compile-time constant
- [x] 3.2 Build recursive analyzer model descriptions for concrete non-generic classes with const unnamed named-parameter constructors, including caching and active-stack cycle detection; verify invalid constructors, generics, abstract models, factories, positional parameters, and direct or indirect cycles fail contextually
- [x] 3.3 Refactor value validation and rendering to walk recursive model and list shapes while reusing scalar, enum, environment, default, and omission behavior at every leaf; verify nested tables, inline tables, arrays of tables, and arrays of inline tables generate correct constructors in source order
- [x] 3.4 Resolve every nested model reference in the annotated library's import context and include dotted paths plus list indices in failures; verify local and imported fixtures analyze and invalid nested values identify their exact location
- [x] 3.5 Enforce object and collection registry-key restrictions and reject `@Obfus` on object, model-list, or nested-model fields; verify boundary fixtures fail before registry output and do not expose resolved environment values

## 4. Example and Documentation

- [x] 4.1 Extend the external-config example with an automatically inferred nested object and array of tables, regenerate both phases, and verify `g.toml` contains no Dart field-type declarations while example tests read typed nested and model-list values
- [x] 4.2 Demonstrate that a structural TOML edit directly regenerates the corresponding Dart model API without a lock or refresh step; verify an integration test changes a nested schema and observes the deterministic generated diff
- [x] 4.3 Document automatic naming, recursive inference, dotted defaults and enum hints, arrays of tables, handwritten nested models, API-change behavior, and unsupported boundaries in the root and package READMEs and changelogs; verify every documented command matches the existing CLI
- [x] 4.4 Document that `add-structured-schema-generation` supersedes the unimplemented `add-nested-object-support` plan and verify the older change is not included in the implementation or archive path for this work

## 5. Repository Verification

- [x] 5.1 Format changed Dart files and run `dart analyze`, `dart test tomg`, and `dart test tomgen`; verify every command exits successfully
- [x] 5.2 Delete only reproducible example outputs, rebuild with `dart run tomgen build -- --delete-conflicting-outputs`, and run `dart test example`; verify the clean two-phase workflow succeeds and generated TOML values remain build-time-only
- [x] 5.3 Run publish dry runs for `tomg` and `tomgen`; verify both packages report zero warnings and exclude transient ownership or recovery files
- [x] 5.4 Run `openspec validate add-structured-schema-generation --strict` and `git diff --check`; verify the change artifacts and implementation patch pass both checks

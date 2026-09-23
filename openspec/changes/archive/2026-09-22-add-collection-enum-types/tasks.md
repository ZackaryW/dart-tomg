# Tasks

## 1. Generator Behavior Fixtures

- [x] 1.1 Add generator fixtures for present nullable scalar values, omitted optional nullable parameters, and missing required nullable parameters; verify focused tests preserve Dart constructor presence semantics
- [x] 1.2 Add local and prefixed-import enum fixtures covering valid values, case-sensitive invalid values with allowed-name diagnostics, enum lists, enum registry keys, and duplicate enum keys; verify generated references analyze in the annotated library
- [x] 1.3 Add list fixtures for every supported scalar element type, preserved ordering, explicit constant output, element-level environment references, and indexed conversion failures; verify focused generator tests cover successful and failing paths without leaking environment values
- [x] 1.4 Add rejection fixtures for whole-list environment strings, nested lists, collection registry keys, and `@Obfus` on enum or list fields; verify each failure names the source and precise field path

## 2. Type-Aware Constant Generation

- [x] 2.1 Refactor scalar detection and rendering to use analyzer type structure with nullability separated from the underlying type; verify all existing scalar, environment, key, obfuscation, and double tests remain green
- [x] 2.2 Implement exact enum-member conversion and constant reference rendering, including allowed-member diagnostics and canonical enum-key collision tracking; verify the enum fixtures pass for local and prefixed imported types
- [x] 2.3 Implement typed constant `List<T>` rendering for supported scalar and enum elements, resolving environment references at each scalar leaf and carrying zero-based index paths; verify the list and environment fixtures pass
- [x] 2.4 Enforce collection-key, nested-list, and enum/list obfuscation boundaries before output or companion generation; verify all unsupported cases fail contextually and produce no partial output

## 3. Example and Documentation

- [x] 3.1 Extend the end-to-end example with a domain enum, a scalar or enum list, and an optional nullable field, then regenerate output and verify example tests observe typed constant values and the nullable default
- [x] 3.2 Document the supported type matrix, exact enum spelling, nullable omission rules, list-item environment behavior, and unsupported boundaries in the package READMEs and changelog; verify every documented example matches generated syntax

## 4. Verification

- [x] 4.1 Format changed Dart files and run `dart analyze`, `dart test tomg`, `dart test tomgen`, workspace code generation, and `dart test example`; verify every command succeeds
- [x] 4.2 Run `openspec validate add-collection-enum-types --strict` and `git diff --check`; verify the change artifacts and working-tree patch pass both checks

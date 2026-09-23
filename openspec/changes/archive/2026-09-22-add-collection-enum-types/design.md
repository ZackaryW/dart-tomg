# Design

## Context

See `proposal.md` for motivation. The generator currently resolves an optional environment reference and then renders a value through a display-string switch for four scalar Dart types. TOML arrays already arrive from `TomlDocument.toMap()` as lists, while analyzer exposes nullability, generic arguments, and enum declarations through structured type metadata. Generated values must remain valid constant expressions, and existing omission, registry-key, validation, and obfuscation behavior must remain stable.

The completed `add-env-substitution` change is still unarchived. This change uses its established syntax and resolution order without duplicating or changing that syntax.

## Goals / Non-Goals

**Goals:**

- Render supported values from analyzer type structure rather than matching complete display strings.
- Keep environment resolution, type conversion, validation, duplicate-key comparison, and source rendering consistent for scalar and list elements.
- Produce precise paths such as `production.tags[2]` for nested validation failures.
- Preserve compile-time constness for every successful registry.

**Non-Goals:**

- Nested custom models, maps, sets, records, nested lists, arrays of tables, and TOML date/time values.
- A TOML null extension or a string sentinel that means null.
- Parsing one environment variable into multiple list elements.
- Obfuscating enum or collection values.

## Decisions

### Use a recursive type-aware constant renderer with an intentionally shallow public type set

Replace the complete-type-name switch with a renderer that inspects nullability, scalar interfaces, enum elements, and `List` type arguments. It recursively renders list items against the element type, but explicitly rejects another list or any unsupported type at that level. This creates an extensible internal shape without implicitly promising arbitrary serialization.

String matching remains appropriate only for identifying SDK scalar element names after resolving aliases and nullability; enum and generic classification use analyzer elements and type arguments. Tests cover enums declared locally and imported with a prefix so generated references remain valid in the annotated library.

*Alternative:* append `String?`, each enum, and each list spelling to the current switch. Rejected because it cannot enumerate user enums safely and becomes fragile around nullability, prefixes, aliases, and generic arguments.

### Preserve Dart constructor presence semantics for nullable parameters

Nullability changes which present values are accepted, not whether a named argument is required. Optional omitted parameters remain omitted so their Dart default, including implicit null, applies. Required nullable parameters remain required. No TOML spelling maps to `null`.

*Alternative:* treat an omitted required nullable parameter as an explicit `null`. Rejected because it erases the distinction deliberately expressed by Dart's `required` modifier.

### Represent enums by exact Dart member names

A TOML string maps case-sensitively to the target enum's declared member name and renders as a constant enum reference. An invalid member reports all allowed names. Enum keys use the resolved enum member identity for duplicate detection. Lists apply the same conversion to each item.

*Alternative:* normalize case or support custom wire names. Rejected for this slice because normalization can make distinct naming conventions ambiguous, while custom names require a new annotation contract.

### Resolve environment references at scalar leaves

Walk a TOML array alongside its declared element type and apply the existing environment resolver to each scalar leaf before enum matching or scalar conversion. A string supplied for the list itself remains a type mismatch. This keeps `$VAR` meaning one value and avoids delimiter and escaping rules.

### Emit explicit typed constant list literals

Render lists as `const <T>[...]`, retaining order and the declared element type. Explicit const syntax makes the guarantee apparent and remains valid inside the generated const object and map.

### Keep registry keys scalar or enum

Enum keys are useful and have value equality. Collection keys are rejected before entry rendering because Dart list equality is identity-based and would make lookup and duplicate detection surprising. Nullable keys continue to require a supplied non-null TOML value because the registry key field is always required in each table.

### Reject unsupported obfuscation before companion generation

If `@Obfus` targets an enum or list, fail at its table field with the declared type and path. The codec remains limited to `String`, `int`, and `double`, and the generator does not introduce collection decode wrappers.

## Risks / Trade-offs

- [Analyzer APIs expose aliases and import prefixes differently across releases] → Use structured type identity for classification and add generated-code fixtures for local, imported, prefixed, nullable, and generic types.
- [Recursive rendering accidentally admits nested lists] → Track rendering depth and reject a list element whose target type is itself a collection.
- [Environment conversion errors expose sensitive values inside arrays] → Reuse the current non-leaking environment diagnostics and include only variable name and indexed field path.
- [Long enum member lists create noisy errors] → Keep the allowed-name list deterministic and complete because it is actionable schema information.
- [Existing scalar behavior regresses during renderer replacement] → Retain the current scalar, duplicate-key, environment, obfuscation, and floating-point fixtures and add focused regression cases around the new branches.

## Migration Plan

This is additive for existing valid inputs. Implement and verify the renderer behind the existing annotation API, regenerate the example, and document the expanded type matrix. Rolling back restores the former scalar-only rejection behavior and requires no generated-data migration.

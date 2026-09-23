# Design

## Context

See [proposal.md](proposal.md) for motivation. `tomgen` currently hands parsed
TOML scalar values directly to type-specific literal rendering and obfuscation.
The generator runs in a Dart VM process, while its output must remain a
dependency-free `const` registry usable on every Dart platform.

Process environment values are ambient inputs that build_runner does not track
in its asset graph. Tests also need deterministic lookup without mutating the
test process environment.

## Goals / Non-Goals

**Goals:**

- Keep the syntax small, unambiguous, and usable for every supported scalar
  constructor type.
- Preserve a clear escape for literal dollar-prefixed strings.
- Apply resolution consistently to ordinary fields, registry keys, and
  obfuscated fields.
- Avoid exposing environment values in errors.

**Non-Goals:**

- Runtime environment lookup or runtime TOML parsing.
- Shell expansion, interpolation within larger strings, recursive defaults, or
  `${VAR}` syntax.
- Reading `.env` files or introducing another dependency.
- Automatically detecting environment-only changes in build_runner watch mode.

## Decisions

### Recognize only whole-string references

A string is a reference only when it starts with a single `$` and the remainder
matches `VAR` or `VAR=default`. Variable names use the portable pattern
`[A-Za-z_][A-Za-z0-9_]*`. Split the default on the first `=` and preserve the
rest verbatim. Strings with an embedded dollar remain literal.

Whole-string matching avoids partial substitution and quoting rules. Shell-like
`${VAR}` and interpolation inside larger text were considered but would expand
the grammar and make literal handling harder to predict.

### Use `$$` as the leading-dollar escape

A string beginning with `$$` drops exactly one leading dollar and bypasses
lookup. A string beginning with one dollar that fails the grammar is an error.
This makes typos visible and provides a direct migration for literal values
that previously began with `$`.

Treating malformed references as ordinary text was considered but would make a
mistyped environment reference silently ship as a literal.

### Resolve to a typed value before rendering

Add a resolution step that receives the TOML value, target Dart type, and field
context. Non-string TOML scalars pass through unchanged. A matching reference
selects the environment value by key presence, then converts it to `String`,
base-10 `int`, `double`, or exact lowercase `bool`. Defaults use the same
conversion and are never recursively expanded.

The resolved typed value feeds key comparison, constructor literal rendering,
and optional obfuscation. Centralizing this step prevents the map key and
constructor argument from resolving differently.

### Inject an environment snapshot into the generator

The normal builder constructs the generator with a snapshot of the build
process environment. The generator accepts an alternate map for builder tests,
allowing present, absent, empty, defaulted, and invalid values to be tested
without changing global process state.

Reading `Platform.environment` at every field was considered but provides no
benefit and makes one generation susceptible to an externally changing map.

### Treat environment changes as explicit rebuild inputs

Documentation will state that changing only an environment variable might not
invalidate build_runner's asset graph. A clean build guarantees regeneration:
run `dart run build_runner clean`, then the normal build command. TOML edits
also invalidate generation normally.

An environment snapshot file could make changes trackable, but generating and
managing such a file would turn this into a separate configuration system.

### Keep sensitive values out of diagnostics

Missing and conversion errors name the variable, expected type, TOML source,
table, and field. They do not include the resolved value. Generated plaintext
is expected for ordinary fields; users must mark a supported field `@Obfus` if
they want basic artifact obfuscation, with the existing security limitations.

## Risks / Trade-offs

- [A cached build keeps an old environment value] → Document the required clean
  rebuild when only ambient environment changes.
- [Existing literal strings begin with a single `$`] → Require `$$` and explain
  this behavior clearly as part of the new syntax.
- [Environment values become embedded in generated artifacts] → Document
  build-time embedding and the existing `@Obfus` limitations.
- [Platform environments use different naming conventions] → Enforce a portable
  variable-name grammar and retain platform case sensitivity.

## Migration Plan

1. Add deterministic builder tests using injected environment maps.
2. Implement parsing, lookup, conversion, and contextual errors before literal
   rendering and key validation.
3. Add an environment-backed example without requiring a developer-specific
   environment variable by using fallback syntax.
4. Update README, generator errors, and changelog documentation.
5. Regenerate, analyze, and run all workspace tests plus strict OpenSpec
   validation.

Rollback removes the syntax handler and example; no runtime data migration is
required.

# Proposal

## Why

Registries sometimes need deployment-specific values that should be selected
when Dart code is generated rather than committed directly to TOML. A compact
TOML string syntax can provide required environment lookup and explicit
fallbacks while preserving typed `const` output.

## What Changes

- Interpret a whole TOML string of the form `$VAR` as a required build-process
  environment variable reference.
- Interpret `$VAR=default` as the same lookup with a literal fallback used only
  when `VAR` is absent.
- Convert resolved strings to the annotated constructor parameter's supported
  scalar type and report contextual errors for missing or invalid values.
- Resolve environment references before registry key validation and `@Obfus`
  encoding.
- Treat `$$` at the start of a TOML string as an escape for a literal leading
  dollar sign, preserving a way to generate values such as `$VAR`.
- Document that environment changes are ambient build inputs and require a
  clean or otherwise invalidated build_runner build to guarantee regeneration.

## Capabilities

### New Capabilities

- `environment-substitution`: Defines build-time environment lookup, defaults,
  escaping, scalar conversion, errors, and interaction with generated output.

### Modified Capabilities

- `toml-codegen`: Resolve environment references before typed instance mapping
  and registry key uniqueness validation.
- `field-obfuscation`: Encode resolved environment plaintext rather than the
  reference syntax for fields marked `@Obfus`.

## Impact

The change affects `tomgen` parsing and error reporting, builder tests, the
example package, and user documentation. It adds no runtime dependency and does
not make environment variables available after generation; resolved values
remain compile-time constants embedded in generated Dart.

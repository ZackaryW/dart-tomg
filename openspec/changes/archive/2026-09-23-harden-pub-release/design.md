# Design

## Context

See [proposal.md](proposal.md) for motivation. The generator currently maps
known constructor parameters but ignores surplus TOML keys, and it emits map
entries without checking key equality. Numeric obfuscation XORs IEEE-754 bits;
some encoded bit patterns cannot be represented safely by the current
`double.toString()` output. The monorepo uses path dependencies, so its local
manifests differ from publishable manifests.

The packages require Dart 3.12.2, which supports Pub workspaces. Workspace
members automatically resolve compatible sibling packages locally while their
declared hosted constraints remain intact for consumers.

## Goals / Non-Goals

**Goals:**

- Fail early with source and table context for configuration that would create
  incomplete or ambiguous registries.
- Prove the generator behavior through fixture-based builder tests.
- Keep the checked-in dependency declarations valid for both local development
  and publication.
- Define exactly which obfuscated doubles can be emitted without losing bits.

**Non-Goals:**

- Dotenv loading, recursive environment expansion, or runtime TOML parsing.
- Cryptographic secrecy for values embedded in application artifacts.
- Expanding supported field types beyond the current scalar set.
- Publishing either package as part of implementation.

## Decisions

### Validate each table before rendering it

Compare every table key with the unnamed constructor's named parameters and
reject the first unknown key with the TOML source and table name. Track registry
key values using Dart equality while iterating and reject a repeated value with
both table names. Validation occurs before returning generated source, so
source_gen cannot combine partial output.

Allowing unknown keys was considered, but it hides misspellings and stale
configuration. A configurable permissive mode adds API surface without a known
0.1.0 use case.

### Test through the public builder boundary

Use builder test fixtures to provide annotated Dart and TOML assets, then assert
generated part content or contextual generation failures. Keep codec tests in
`tomg` for bit-level behavior and retain the example package as the end-to-end
integration check.

Testing private helpers directly was considered, but it would couple tests to
the current generator decomposition while missing asset resolution and
source_gen integration.

### Reject unrepresentable encoded doubles

After encoding a TOML `double`, require a finite ciphertext. Render it with
Dart's round-trip decimal representation, parse that representation, and verify
the parsed ciphertext has the same 64-bit pattern before emitting it. Verify
that decoding reproduces the source value's 64-bit pattern as well. Reject a
value with a contextual generation error if any check fails.

Changing the public codec or storing double ciphertext as a string would either
break existing output or change the annotated field type. Special constants
such as `double.nan` cannot preserve arbitrary NaN payload bits, so rejection is
the narrowest safe behavior for 0.1.0.

### Use a Pub workspace for sibling resolution

Add a non-publishable root manifest listing `tomg`, `tomgen`, and `example` as
workspace members. Each member opts into workspace resolution. Replace path
dependencies with compatible hosted constraints; within the workspace Pub uses
the local package, while published consumers resolve the hosted package.

Dependency overrides and release-time manifest rewriting were considered.
Overrides can mask incompatible constraints, and rewriting leaves room for
publishing a manifest different from the one tested.

### Document explicit environment references and their build boundary

Document `$VAR` as a required build-process environment reference,
`$VAR=default` as the same reference with a literal fallback, and `$$VAR` as the
escaped literal `$VAR`. Only a leading dollar prefix is special, defaults are
not recursively expanded, and generated registries have no runtime environment
dependency. The release guidance also calls out that environment changes alone
may not invalidate build_runner's asset graph, so maintainers can force a clean
regeneration when environment-derived output must change.

## Risks / Trade-offs

- [Existing TOML files contain unused metadata keys] → Treat this as a clear
  pre-1.0 validation change and include the field and table in the error.
- [A rare finite double encodes to an unrepresentable bit pattern] → Fail with
  an actionable error rather than generating code that fails later or decodes
  incorrectly.
- [Workspace migration removes member lockfiles and package configs] → Commit
  the root resolution and verify all commands from both root and member paths.
- [The generator package cannot pass hosted dependency validation until `tomg`
  0.1.0 is visible on pub.dev] → Keep the documented release order and run the
  second dry run after the first package is available.

## Migration Plan

1. Add generator and codec tests that expose the unsafe cases.
2. Implement validation and safe double literal emission.
3. Migrate manifests to a Pub workspace and resolve once at the root.
4. Update repository and package documentation.
5. Run analysis, unit tests, regeneration, end-to-end tests, strict OpenSpec
   validation, and publication dry runs where hosted dependency availability
   permits.

Rollback consists of reverting the workspace metadata and validation changes;
no published API or stored data migration is involved.

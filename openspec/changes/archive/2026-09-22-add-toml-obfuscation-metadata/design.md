# Design

## Context

See `proposal.md` for motivation. The generator currently parses the whole TOML
document as registry rows, derives the obfuscated field set only from Dart
annotations, and uses that set for encoding and companion generation. The new
metadata must be removed before row validation while leaving the existing codec
and generated API unchanged.

## Goals / Non-Goals

**Goals:**

- Make obfuscation intent reviewable in TOML without letting TOML silently alter
  the Dart storage or decode contract.
- Reject malformed or drifting declarations before any generated output.
- Preserve byte-for-byte generation behavior for files without metadata.

**Non-Goals:**

- Enabling obfuscation from TOML without matching Dart `@Obfus` annotations.
- Per-row obfuscation policies, nested field paths, codec selection, keys, or
  encryption settings in TOML.
- Emitting metadata into generated Dart or runtime assets.

## Decisions

### Use one reserved top-level metadata table

`[__tomg]` separates generator configuration from each registry row and leaves
room for explicitly designed metadata keys later. For this change its schema is
closed: it requires exactly `obfuscate`, an array of unique strings. Environment
substitution does not apply to metadata because field names are schema, not data.

The alternative is a special key inside every row. That repeats a file-wide
policy, permits rows to disagree, and collides with constructor-field checking.
A root scalar such as `__tomg_obfuscate` is less extensible and mixes generator
configuration with data values.

The `__tomg` name is reserved whenever present. This gives malformed metadata
deterministic diagnostics, at the cost of requiring any existing registry row
with that name to be renamed.

### Keep Dart annotations operationally authoritative

The Dart field annotation determines encoding, companion generation, and the
hand-written `Obfuscated<D>` contract. TOML metadata is an independently
reviewable assertion. When present, compare its normalized string set with the
Dart annotation set and require equality before rendering rows.

The alternative is to let TOML alone activate obfuscation. A class without the
annotation and decode interface would then store ciphertext without a reliable
typed access path. Using a union would also hide drift and could unexpectedly
change shipped values.

### Validate metadata before registry rows

After TOML parsing, remove `__tomg` from a mutable copy of the document, validate
its closed schema and field names, then compare it with the Dart set. Only after
that succeeds should ordinary type validation and row rendering run. Diagnostics
name the TOML source, metadata path, class, and field names, but never include
registry values.

The alternative is to skip `__tomg` inside the row loop. That spreads metadata
handling across data validation and risks partially rendered output or generic
missing-key errors.

### Compare sets while rejecting duplicate declarations

Array order has no policy meaning, so equality is set-based. Duplicate strings
are still an error because accepting them can conceal copy-and-paste mistakes.
Report missing Dart or TOML declarations separately so the repair is clear.

### Keep generated code unchanged

Matching metadata only confirms the annotations already controlling generation.
It produces no constants, comments, fields, or runtime metadata. This keeps
artifacts stable and avoids exposing policy details beyond the existing typed
companion.

## Risks / Trade-offs

- [TOML and Dart duplicate the same policy] → Exact equality turns duplication
  into a checked assertion rather than two competing sources of truth.
- [An existing registry uses `__tomg` as an entry name] → Document the reserved
  name and fail with a metadata-specific migration error.
- [Future metadata additions weaken validation] → Keep a closed key set and add
  every future key through a separate behavior contract.
- [Error text reveals sensitive TOML values] → Report only source, metadata path,
  class, and field names; never render row values in metadata diagnostics.

## Migration Plan

Metadata is opt-in. Existing files without `[__tomg]` require no change. To
adopt it, add `obfuscate` with the complete set of Dart `@Obfus` field names and
regenerate. Rename any ordinary registry row named `__tomg` before upgrading.
Rollback consists of removing the metadata table and using the earlier generator;
the Dart annotations and generated runtime contract remain unchanged.

# Proposal

## Why

`tomgen` 0.1.0 cannot be added to the first real Flutter consumer because its
generator dependency bounds require analyzer 14 while that consumer resolves
analyzer 10.0.1. The same consumer needs two currently uncontracted behaviors:
obfuscated registry keys and TOML sources committed at the enclosing pub
workspace root rather than copied into the consuming package.

## What Changes

- Widen `tomgen`'s generator-stack constraints so it resolves next to analyzer
  10.x through 14.x:
  - `analyzer: '>=10.0.1 <15.0.0'`
  - `source_gen: '>=4.2.3 <5.0.0'`
  - `dart_style: '>=3.1.7 <4.0.0'`
  - `build` remains `^4.0.0`.
- Add a lowest-bounds verification gate that pins the declared minimum
  generator stack and runs the generator, consumer, and example gates.
- Specify and test obfuscated registry keys. Generated maps use the key field's
  ciphertext, and consumers look up entries with the public `TomgCodec`.
- Allow a TOML-first target to reference a source outside its package but inside
  its nearest enclosing pub workspace. Lexical and symlink escapes outside that
  boundary remain rejected; without an enclosing workspace, sources remain
  package-contained.
- Digest-pin external TOML content in the generated model annotation. Phase two
  reads an external source directly, verifies its SHA-256 digest, and reports an
  actionable stale-generation error when phase one has not been rerun.
- Keep package-local source generation byte-for-byte compatible: it continues
  to use build-runner assets and emits no digest.
- Release `tomg` 0.2.0 and `tomgen` 0.2.0 together, publishing `tomg` first.

## Capabilities

### New Capabilities

- `external-toml-sources`: defines workspace-bounded TOML sources, digest-pinned
  phase handoff, stale-source rejection, fresh-clone behavior, and compatibility
  with package-local sources.

### Modified Capabilities

- `field-obfuscation`: adds a requirement that makes an obfuscated registry key
  supported. The map key is ciphertext, the plaintext key is absent from the
  generated source, and lookup goes through the public codec.
- `release-readiness`: adds a requirement to verify the declared lower bounds
  of the generator dependency stack, so published ranges are proven rather than
  merely declared.

## Impact

- `tomg/lib/src/annotations.dart`: `TomgRegistry` gains an optional digest
  parameter while preserving existing 0.1.x call sites.
- `tomgen/pubspec.yaml`: generator dependency ranges widen, `tomg` advances to
  `^0.2.0`, and `tomgen` advances to 0.2.0.
- `tomgen/lib/src/cli/**`: project discovery, source containment, annotation
  emission, and documentation gain workspace-external source support.
- `tomgen/lib/src/tomg_generator.dart`: digest-bearing sources use verified
  direct filesystem reads; package-local sources retain the build-step path.
- `.github/workflows/ci.yml`: a dedicated lowest-bounds job is added.
- Tests cover model-first and TOML-first obfuscated keys, containment attacks,
  digest mismatch, fresh-clone builds, and unchanged package-local output.
- `README.md`, package changelogs, and `PUBLISHING.md` document the new workflow
  and coordinated 0.2.0 release.
- This unblocks the separate appbuilder-clients change
  `adopt-tomg-registries`; that downstream implementation remains out of scope.

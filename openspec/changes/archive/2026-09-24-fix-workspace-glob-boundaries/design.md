# Design

## Context

See `proposal.md` for motivation. Both CLI configuration loading and the
build_runner generator call `discoverSourceBoundary`, so one correction can
keep the two phases aligned. The package already depends on `package:glob`.
Pub also generates `.dart_tool/pub/workspace_ref.json`, but that file is build
state rather than a documented package API and is unavailable before `pub get`.

## Goals / Non-Goals

**Goals:**

- Match explicit and glob workspace members using the same path form on every
  supported host platform.
- Retain nearest-workspace selection and canonical filesystem containment.
- Prove the behavior through unit and real-process phase-one and phase-two tests.

**Non-Goals:**

- Depending on Pub-generated `.dart_tool` metadata for correctness.
- Reimplementing Pub dependency resolution or accepting sources outside the
  selected workspace.
- Changing annotation, digest, configuration, or generated-source formats.

## Decisions

### Match the canonical package path relative to each candidate workspace

For each ancestor pubspec with a workspace list, canonicalize the workspace
directory, derive the canonical package's relative path, normalize that path to
forward-slash form, and match it against each relative workspace declaration
with `package:glob`. This handles literal entries and Dart 3.11+ glob entries
through one rule while leaving absolute entries ineligible.

Expanding each glob against the filesystem was considered, but direct matching
is deterministic, avoids directory traversal, and only needs to answer whether
the already-discovered package is a member.

### Keep canonical containment separate from membership syntax

A glob match only identifies the source boundary. Existing normalized-path and
resolved-symlink checks continue to decide whether a configured source is safe.
The candidate package must itself resolve beneath the canonical workspace root
before its relative path is matched.

Using `.dart_tool/pub/workspace_ref.json` was considered. It accurately records
the resolved root after `pub get`, but relying on generated private state would
make otherwise valid generation depend on its presence and freshness.

### Exercise both consumers of the shared helper

Unit coverage will verify literal members, glob members, nonmatching globs, and
containment rejection. The black-box `ci_test` fixture will use a glob member
and run `tomgen build`, which exercises phase one and build_runner phase two in
an isolated hosted-style consumer workflow.

## Risks / Trade-offs

- **Glob semantics diverge from Pub** → Use the existing Dart `glob` package,
  POSIX-style workspace patterns, and fixtures that Pub resolves successfully.
- **A broad glob grants an unintended boundary** → Require the canonical package
  path to match and retain all source path and symlink containment checks.
- **Platform separators change matching** → Convert the canonical relative path
  from host segments into Pub's forward-slash workspace syntax before matching.

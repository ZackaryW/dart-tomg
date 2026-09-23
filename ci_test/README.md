# dart-tomg CI tests

This non-published workspace package contains repository-level verification that
does not belong in either public package archive.

Run it from the repository root:

```sh
dart test ci_test
```

The consumer test creates isolated temporary Dart packages and exercises both
supported initializer paths:

- zero-argument `tomgen init` followed by `tomgen build`;
- custom initialization from an existing external TOML source.

Each package resolves the current checkout through path dependencies, verifies
that external TOML remains unchanged and outside `lib/`, checks that no runtime
asset declaration was added, builds the generated model and const registry, and
runs `dart analyze` over the result.

The workflow contract test parses [the CI workflow](../.github/workflows/ci.yml)
and checks its triggers, read-only permissions, SDK matrix, commands, generated
diff gate, and unsuppressed publication dry-runs. It also proves that weakened
trigger, permission, test, and publication configurations are rejected.

Focused runtime and generator behavior remains under `tomg/test/` and
`tomgen/test/`. The runnable checked-in registry remains under `example/`.

See [PUBLISHING.md](../PUBLISHING.md) for the complete local sequence matching
the automated workflow.

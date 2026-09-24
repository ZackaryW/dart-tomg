# Publishing tomg and tomgen

This repo holds two packages. When both advance, they must be published **in
order**, because `tomgen` depends on `tomg`:

```
  tomg (no deps on tomgen)  -->  publish first
       |
       v
  tomgen depends on tomg    -->  publish second, only once tomg is live
```

The repository is a Pub workspace. `tomgen` declares the publishable hosted
constraint `tomg: ^0.2.0`, while workspace resolution automatically uses the
local `tomg` package during development. No manifest rewriting is required.

## Validate the workspace

GitHub Actions runs analysis, tests, generation, and archive validation on the
minimum supported Dart SDK (`3.12.2`) and the current stable SDK. Formatting is
checked once with the current stable SDK because Dart formatter output can change
between SDK releases. From a clean repository checkout, run the same gates from
the repository root, using the current stable SDK for the format command:

```
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart test tomg
dart test tomgen
dart test ci_test
cd example
dart run tomgen build
dart test
cd ..
git diff --exit-code -- example/lib/generated
dart pub -C tomg publish --dry-run
dart pub -C tomgen publish --dry-run
```

The `ci_test/` package creates isolated consumers for starter and custom
`tomgen init` builds and verifies the CI workflow contract itself. The generated
diff gate proves the checked-in example matches its TOML inputs. Publication
warnings fail CI; do not use `--ignore-warnings` or `--skip-validation`.

Then inspect the complete working tree. Publishing warns about uncommitted
files, so perform release dry runs from the exact commit intended for release.

## Verify declared lower bounds

The dedicated CI job pins only the generator stack whose public lower bounds
tomgen declares. Reproduce it from a scratch checkout so the temporary workspace
override never affects the working repository:

```sh
scratch_dir="$(mktemp -d)"
git archive HEAD | tar -x -C "$scratch_dir"
cd "$scratch_dir"
printf '%s\n' \
  'dependency_overrides:' \
  '  analyzer: 10.0.1' \
  '  source_gen: 4.2.3' \
  '  dart_style: 3.1.7' \
  '  test: 1.31.0' \
  > pubspec_overrides.yaml
dart pub get
dart analyze
dart test tomgen
dart test ci_test
cd example
dart run tomgen build
dart test
cd ..
git diff --exit-code -- example/lib/generated
```

The expected 0.2.1 baseline is 107 tomgen tests, 3 isolated-consumer tests, 9
example tests, and no generated example diff. Remove the scratch directory
after inspection.

## Releasing tomgen 0.2.1

Version 0.2.1 fixes workspace boundary discovery for glob members such as
`apps/*`. It changes only the generator package; `tomg` remains at 0.2.0 and
already satisfies tomgen's hosted dependency constraint. Complete the default
and lowest-bounds gates, then publish `tomgen` 0.2.1.

The publication dry run is already part of validation. Publish only after every
gate passes:

```sh
dart pub -C tomgen publish
```

## Releasing a new version of both

Bump `tomg`'s version, update `tomgen`'s hosted `tomg: ^x.y.z` constraint and
its own version, resolve and test the workspace, then publish in the same order.
Workspace resolution continues to use the local compatible package throughout.

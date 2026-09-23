# Publishing tomg and tomgen

This repo holds two packages that must be published **in order**, because
`tomgen` depends on `tomg`:

```
  tomg (no deps on tomgen)  -->  publish first
       |
       v
  tomgen depends on tomg    -->  publish second, only once tomg is live
```

The repository is a Pub workspace. `tomgen` declares the publishable hosted
constraint `tomg: ^0.1.0`, while workspace resolution automatically uses the
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

## 1. Publish `tomg`

`dart pub -C tomg publish --dry-run` is already part of validation. Publish only
after every gate passes:

```
dart pub -C tomg publish
```

## 2. Publish `tomgen` after `tomg` is available

Wait until pub.dev can resolve the new `tomg` version, then:

`dart pub -C tomgen publish --dry-run` is already part of validation. After the
new `tomg` version is available:

```
dart pub -C tomgen publish
```

## Releasing a new version of both

Bump `tomg`'s version, update `tomgen`'s hosted `tomg: ^x.y.z` constraint and
its own version, resolve and test the workspace, then publish in the same order.
Workspace resolution continues to use the local compatible package throughout.

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

From the repository root:

```
dart pub get
dart analyze
dart test tomg
dart test tomgen
dart run build_runner build --workspace
dart test example
```

Then inspect the working tree. Publishing warns about uncommitted files, so
perform release dry runs from the exact commit intended for release.

## 1. Publish `tomg`

```
dart pub -C tomg publish --dry-run
dart pub -C tomg publish
```

## 2. Publish `tomgen` after `tomg` is available

Wait until pub.dev can resolve the new `tomg` version, then:

```
dart pub -C tomgen publish --dry-run
dart pub -C tomgen publish
```

## Releasing a new version of both

Bump `tomg`'s version, update `tomgen`'s hosted `tomg: ^x.y.z` constraint and
its own version, resolve and test the workspace, then publish in the same order.
Workspace resolution continues to use the local compatible package throughout.

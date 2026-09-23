# tomgen example

`tomgen` provides a CLI and a build_runner builder. The real runnable package
lives at the top of this repository and demonstrates both phases together.

The real, runnable package lives at the top of this repository. Its TOML files
are outside `lib/` under `config/`; `build.yaml` includes them as build inputs
without declaring them as runtime assets. It covers an obfuscated endpoint
registry and a typed service-plan registry:

<https://github.com/ZackaryW/dart-tomg/tree/main/example>

Clone the repo and, inside that directory, run:

```
dart pub get
dart run tomgen build
dart test
```

See [the main README](../README.md) for the root `g.toml` manifest and the
model-first annotation walkthrough.

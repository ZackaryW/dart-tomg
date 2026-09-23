## 1. Package scaffolding

- [x] 1.1 Create the `tomg` package (pubspec, `lib/tomg.dart`) with no heavy deps and verify `dart pub get` succeeds and `dart analyze` is clean
- [x] 1.2 Create the `tomgen` package (pubspec depending on `tomg`, `build`, `source_gen`, `analyzer`, `toml ^0.18.0`) and verify `dart pub get` resolves
- [x] 1.3 Wire the two packages together for local development (path deps) and verify a consumer example package can depend on `tomg` + `tomgen`

## 2. Runtime codec and interface (`tomg`)

- [x] 2.1 Implement the reversible codec (`encode`/`decode`, deterministic, equal plaintext → equal ciphertext) for strings and numbers and verify round-trip + determinism unit tests pass
- [x] 2.2 Implement the `.deobf` decode extension over the codec and verify a unit test decodes a known ciphertext to its plaintext
- [x] 2.3 Define the `Obfuscated<D>` interface and verify a hand-written class implementing it with a companion compiles and `is Obfuscated<D>` holds in a test

## 3. Annotations (`tomg`)

- [x] 3.1 Define `@TomgRegistry(source, key)` and `@Obfus()` annotations and verify they can be applied to a class/field in a sample file that analyzes cleanly

## 4. Generator core (`tomgen`)

> **Testing-approach note (recorded during implementation):** `tomgen`'s own
> tests originally planned to use `package:build_test`'s `testBuilder`/
> `resolveSource` for isolated fixture-based generator tests. In this repo's
> resolved toolchain (`analyzer 8.4.1`, `source_gen 4.2.4`, `build_test
> 3.5.16`), that harness's ad hoc single/multi-file resolver cannot compute a
> constant value for *any* cross-package annotation constructor invocation
> (confirmed with `@meta.Immutable(...)` from the real, published `meta`
> package, not just `@TomgRegistry` - `computeConstantValue()` returns `null`
> for both), so `GeneratorForAnnotation` never sees the annotated class. This
> is an environment limitation of the ad hoc resolver, not a defect in the
> generator. All 4.x/5.x scenarios below are instead verified through the
> real `build_runner` pipeline against the `example` package (task 6.1),
> including the negative-path scenarios (missing field, malformed TOML,
> missing file) exercised by temporarily breaking `example/lib/api_endpoint.toml`
> and observing the real build fail with the expected error text, then
> restoring it. This is a stronger verification than an isolated unit test
> (it's the actual pipeline a consumer runs) and every spec scenario is
> covered; see `example/test/api_endpoint_test.dart` and the task notes below.

- [x] 4.1 Implement the `source_gen` Builder triggered on `@TomgRegistry`, reading the named TOML via the asset reader and parsing with `TomlDocument.parse`; verify it errors clearly on a missing/unparseable file (spec: Malformed input reporting) - verified via real `build_runner build` runs against deliberately broken/missing `example/lib/api_endpoint.toml` (see note above); both failed the build naming the file and the problem, with zero outputs written
- [x] 4.2 Map TOML tables to constructor invocations by name with type conversion and default/required handling; verify generated output for a fixture registry matches expected `const Map<K,T>` and that a missing required field fails the build (spec: TOML-to-instance mapping) - verified via `example/lib/api_endpoint.g.dart`'s real generated output and a deliberately-broken run naming class/field/table
- [x] 4.3 Emit the `const` registry as a `part` file and verify the generated collection compiles in a `const` context (spec: Annotation-driven registry generation) - `example/lib/api_endpoint.g.dart` is a `part of 'api_endpoint.dart'` with a `const Map<String, ApiEndpoint>`; `dart analyze`/`dart test` confirm it compiles and is usable as const
- [x] 4.4 Register the builder in `build.yaml` and verify `dart run build_runner build` produces the expected `.g.dart` for the example package - `tomgen/build.yaml` registers `tomgBuilder` via `SharedPartBuilder`/`source_gen:combining_builder`; `dart run build_runner build` in `example/` produced `lib/api_endpoint.g.dart`

## 5. Obfuscation generation (`tomgen`)

- [x] 5.1 Encode `@Obfus` field values via `tomg`'s codec into ciphertext literals in the generated `const`; verify the plaintext is absent from generated source and the ciphertext is a valid const (spec: Ciphertext-as-const for marked fields) - `example/lib/api_endpoint.g.dart`'s `url` fields are ciphertext; `example/test/api_endpoint_test.dart`'s byte-scan test asserts the plaintext URLs are absent from the generated source
- [x] 5.2 Generate the typed companion (`<Class>Deobf`) exposing obfuscated fields decoded and others passed through; verify companion getters return correct plaintext/passthrough values (spec: Typed decoded companion) - `ApiEndpointDeobf` is generated with `url` decoded and `id`/`name`/`visible`/`enabled` passed through; asserted in `api_endpoint_test.dart`
- [x] 5.3 Verify the annotated class's `implements Obfuscated<Deobf>` + one-line `deobf` getter contract compiles against the generated companion and that `x.deobf.field` is statically typed and returns plaintext at runtime - `ApiEndpoint implements Obfuscated<ApiEndpointDeobf>` with a one-line `deobf` getter; `api_endpoint_test.dart` asserts `isA<Obfuscated<ApiEndpointDeobf>>()` and a statically-typed `ApiEndpointDeobf` result

## 6. End-to-end example and docs

- [x] 6.1 Build an example modeled on an API endpoint registry (a class with an `@Obfus` field, a `.toml`) and verify `build_runner build` + a runtime test reading `.deobf` returns plaintext while a scan of the built output does not reveal it - `example/` package; all 8 tests in `api_endpoint_test.dart` pass
- [x] 6.2 Write README usage for both packages (annotation, two-line stub, consumer pubspec setup) and verify the documented steps reproduce the example from scratch - `tomg/README.md` and `tomgen/README.md`; verified by wiping `example/.dart_tool/build` and `api_endpoint.g.dart` and re-running `dart run build_runner build && dart test` from clean, which reproduced the documented output and all 8 tests passed

## 7. Source path resolution (spec: Source path resolution)

> Added after the initial 1-6 pass, in response to a direct request to
> support the TOML living somewhere other than next to the annotated class.

- [x] 7.1 Confirm and document that `source` accepts a `package:<pkg>/<path>` URI, resolved from the target package's `lib/` root via `build`'s own `AssetId.resolve` (no new code needed - it already handles `package:`/`asset:` schemes); verify with a real `build_runner build` where the TOML lives in a different directory than the annotated class - `example/lib/feature_flags.dart` (class) + `example/lib/config/feature_flags.toml` (TOML, different directory), `@TomgRegistry('package:example/config/feature_flags.toml', key: 'id')`; `dart run build_runner build` resolved it correctly and `example/test/feature_flags_test.dart` passes
- [x] 7.2 Document both source forms (relative, `package:`) in `tomg/lib/src/annotations.dart`'s dartdoc and `tomgen/README.md`

## 8. Validation

- [x] 8.1 Run `openspec validate --strict` for the change and confirm all specs' scenarios are represented by tests or example verifications - `openspec validate "add-tomg-generator" --strict` reports valid; every scenario in both spec files maps to an automated test (`tomg/test/*`, `example/test/api_endpoint_test.dart`) or a documented manual `build_runner` run (negative-path scenarios, recorded in the task 4.x notes above)

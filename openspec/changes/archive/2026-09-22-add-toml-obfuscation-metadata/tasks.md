# Tasks

## 1. Metadata and Agreement Fixtures

- [x] 1.1 Add generator fixtures for matching `[__tomg]` declarations in different array orders and for metadata-free files; verify matching metadata succeeds, is absent from output, and metadata-free generated output remains unchanged
- [x] 1.2 Add malformed metadata fixtures for non-table `__tomg`, missing or unknown keys, non-array values, non-string items, duplicate names, and an ordinary row using the reserved name; verify source-specific metadata diagnostics and no partial output
- [x] 1.3 Add agreement fixtures for TOML fields missing from Dart, Dart fields missing from TOML, unknown constructor fields, and unsupported obfuscation targets; verify each error identifies the source, class, and relevant field without including registry values

## 2. Generator Metadata Processing

- [x] 2.1 Extract and remove the reserved `__tomg` table immediately after TOML parsing, validate its closed `obfuscate` schema as unique strings, and verify malformed metadata fixtures pass
- [x] 2.2 Compare the normalized TOML obfuscation set with constructor fields and the Dart `@Obfus` set before type validation or row rendering; verify matching, missing, extra, unknown, and unsupported field fixtures pass
- [x] 2.3 Keep metadata out of registry iteration and generated code while preserving the existing Dart-only path when metadata is absent; verify successful output and regression fixtures are byte-for-byte stable where applicable

## 3. Example and Documentation

- [x] 3.1 Add matching `[__tomg]` obfuscation metadata to the external `api_endpoints.toml`, regenerate the example, and verify tests prove the metadata is not a registry entry, URLs are ciphertext at rest, plaintext is absent from generated source, and `.deobf` returns the original URL
- [x] 3.2 Document the metadata syntax, exact-match rule, optional compatibility path, reserved table migration, supported field boundaries, and TOML/Dart example in the root and package READMEs and changelogs; verify every snippet matches the runnable example

## 4. Verification

- [x] 4.1 Format changed Dart files and run `dart analyze`, `dart test tomg`, `dart test tomgen`, workspace code generation, and `dart test example`; verify every command succeeds
- [x] 4.2 Run `openspec validate add-toml-obfuscation-metadata --strict` and `git diff --check`; verify the change artifacts and working-tree patch pass both checks

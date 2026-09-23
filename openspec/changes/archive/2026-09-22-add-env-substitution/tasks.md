# Tasks

## 1. Reference Parsing and Lookup

- [x] 1.1 Add deterministic builder tests for required lookup, fallback lookup, empty present values, defaults containing `=`, escaping, embedded dollars, and malformed references; verify the focused tests initially expose unsupported behavior
- [x] 1.2 Inject an environment snapshot into the generator and implement `$VAR`, `$VAR=default`, and `$$` parsing; verify lookup and syntax tests pass
- [x] 1.3 Add missing-variable error coverage that checks variable, source, table, and field context without leaking a value; verify the focused error test passes

## 2. Typed Integration

- [x] 2.1 Add builder tests for environment-backed `String`, `int`, `double`, and `bool` fields plus invalid conversions; verify every supported scalar type and safe error output is covered
- [x] 2.2 Resolve environment text to typed values before literal rendering; verify scalar conversion tests pass
- [x] 2.3 Add tests for environment-backed keys, collisions after resolution, and `@Obfus` fields; verify keys use resolved values and generated obfuscated output contains neither reference nor plaintext
- [x] 2.4 Route resolved typed values through key validation and obfuscation; verify the full `tomgen` test suite passes

## 3. Example and Documentation

- [x] 3.1 Add a fallback-backed field to the example TOML and model that requires no machine-specific environment setup; regenerate and verify the example test observes the fallback constant
- [x] 3.2 Document syntax, escaping, type conversion, clean rebuild requirements, constant embedding, and obfuscation limits in the root and `tomgen` READMEs; verify examples match implemented grammar
- [x] 3.3 Update `tomgen` error documentation and changelog; verify documented failures match tested diagnostics

## 4. Verification

- [x] 4.1 Format changed Dart files, regenerate the workspace, and run workspace analysis plus all package tests; verify every command succeeds
- [x] 4.2 Run strict OpenSpec validation and inspect the final diff; verify the separate change is complete and contains no accidental artifacts

/// Marks a class as the target of `tomgen`'s TOML-to-const-registry
/// generation.
///
/// For each top-level table in [source], the generator emits one `const`
/// instance of the annotated class into a generated `Map<K, T>`, keyed by
/// the value of the constructor parameter named [key].
///
/// The annotated class must have a `const` unnamed constructor with named
/// parameters matching the TOML tables' keys.
class TomgRegistry {
  const TomgRegistry(this.source, {required this.key});

  /// Where the TOML file lives. Consumed only at build time - never a
  /// bundled runtime asset. Two forms:
  ///
  ///  - A plain relative path, resolved from the annotated library's own
  ///    directory - e.g. `'api_endpoint.toml'` next to the class, or
  ///    `'../config/api_endpoint.toml'` in a sibling directory.
  ///  - A `package:` URI, resolved from the package's `lib/` root
  ///    regardless of where the annotated class lives - e.g.
  ///    `'package:my_app/config/api_endpoint.toml'` for
  ///    `lib/config/api_endpoint.toml`. The same rule `package:` imports
  ///    already follow.
  ///
  /// (An `asset:package/path` URI is also accepted, resolved from the
  /// package root rather than `lib/`, for a TOML that lives outside `lib/`
  /// - the consuming package's own `build.yaml` must then add that
  /// location to its build `sources:`, since `lib/` is the only directory
  /// `build_runner` scans by default.)
  final String source;

  /// The name of the constructor parameter (and field) whose value becomes
  /// this instance's key in the generated registry map.
  final String key;
}

/// Marks a field as obfuscated: `tomgen` stores its value as ciphertext in
/// the generated `const` construction instead of the plaintext, and exposes
/// the decoded value at runtime through the class's generated `Obfuscated<D>`
/// companion.
class Obfus {
  const Obfus();
}

/// Implemented by a `@TomgRegistry`-annotated class that declares at least
/// one `@Obfus` field. [deobf] returns the generated typed companion [D],
/// which exposes every `@Obfus` field decoded to its plaintext and every
/// other field unchanged.
///
/// `build_runner` generators can only emit top-level symbols into a `part`
/// file - they cannot inject a member into a hand-written class. So the
/// companion type [D] is generated, but this one-line implementation is
/// written by hand:
///
/// ```dart
/// class ApiEndpoint implements Obfuscated<ApiEndpointDeobf> {
///   const ApiEndpoint({required this.url});
///
///   @Obfus()
///   final String url;
///
///   @override
///   ApiEndpointDeobf get deobf => ApiEndpointDeobf(this);
/// }
/// ```
///
/// `x.deobf.url` then returns the decoded plaintext, statically typed as
/// `String`, while `x.url` remains the `const` ciphertext.
abstract interface class Obfuscated<D> {
  D get deobf;
}

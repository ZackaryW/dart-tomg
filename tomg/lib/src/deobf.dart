import 'codec.dart';

/// Decodes a ciphertext [String] produced by `tomgen`'s field obfuscation
/// back to its original plaintext, at runtime.
extension TomgStringDeobf on String {
  String get deobf => TomgCodec.decodeString(this);
}

/// Decodes a ciphertext [int] produced by `tomgen`'s field obfuscation back
/// to its original plaintext, at runtime.
extension TomgIntDeobf on int {
  int get deobf => TomgCodec.decodeInt(this);
}

/// Decodes a ciphertext [double] produced by `tomgen`'s field obfuscation
/// back to its original plaintext, at runtime.
extension TomgDoubleDeobf on double {
  double get deobf => TomgCodec.decodeDouble(this);
}

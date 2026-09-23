import 'dart:convert';
import 'dart:typed_data';

/// The reversible, deterministic codec behind `tomg`'s field obfuscation.
///
/// This is obfuscation, not encryption: the goal is keeping a value out of a
/// `strings`/`grep` pass over a shipped build artifact (`main.dart.js`,
/// `libapp.so`, a native/desktop binary), not withstanding a determined
/// reverse-engineer. The keystream below is fixed and public - it exists so
/// the generator's encode and the runtime's decode agree, not to keep a
/// secret.
///
/// Encoding is deterministic: the same plaintext always encodes to the same
/// ciphertext, so equality comparisons on two obfuscated fields work without
/// decoding either one first.
///
/// All operations stay within 32-bit integer arithmetic so behavior is
/// identical across every Dart backend (VM, dart2js, dart2wasm, AOT), not
/// just the ones with native 64-bit ints.
abstract final class TomgCodec {
  static const List<int> _keystream = <int>[
    0x5A,
    0x3C,
    0x91,
    0xE7,
    0x2F,
    0x6D,
    0xB8,
    0x14,
    0xC5,
    0x79,
    0x02,
    0xAD,
    0x4B,
    0xF3,
    0x8E,
    0x61,
  ];

  static const int _intKey = 0x6D2FB814;
  static const int _doubleKeyHi = 0x5A3C91E7;
  static const int _doubleKeyLo = 0x6D2FB814;

  /// Encodes [value] to an opaque ciphertext string. Reversed by
  /// [decodeString].
  static String encodeString(String value) {
    final bytes = utf8.encode(value);
    return base64Url.encode(_xorBytes(bytes));
  }

  /// Decodes ciphertext produced by [encodeString] back to the original
  /// value.
  static String decodeString(String value) {
    final xored = base64Url.decode(value);
    return utf8.decode(_xorBytes(xored));
  }

  /// Encodes [value] to an opaque ciphertext int. Reversed by [decodeInt].
  ///
  /// XOR is its own inverse, so encode and decode are the same operation.
  static int encodeInt(int value) => value ^ _intKey;

  /// Decodes ciphertext produced by [encodeInt] back to the original value.
  static int decodeInt(int value) => value ^ _intKey;

  /// Encodes [value] to an opaque ciphertext double. Reversed by
  /// [decodeDouble].
  ///
  /// Bit-XOR is its own inverse, so encode and decode are the same
  /// operation.
  static double encodeDouble(double value) => _xorDoubleBits(value);

  /// Decodes ciphertext produced by [encodeDouble] back to the original
  /// value.
  static double decodeDouble(double value) => _xorDoubleBits(value);

  static Uint8List _xorBytes(List<int> bytes) {
    final out = Uint8List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      out[i] = bytes[i] ^ _keystream[i % _keystream.length];
    }
    return out;
  }

  static double _xorDoubleBits(double value) {
    final bd = ByteData(8)..setFloat64(0, value);
    final hi = bd.getUint32(0) ^ _doubleKeyHi;
    final lo = bd.getUint32(4) ^ _doubleKeyLo;
    return (ByteData(8)
          ..setUint32(0, hi)
          ..setUint32(4, lo))
        .getFloat64(0);
  }
}

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tomg/tomg.dart';

void main() {
  group('TomgCodec.encodeString / decodeString', () {
    test('round-trips arbitrary strings', () {
      for (final value in <String>[
        'secret',
        'https://api.us-east.example.com',
        'staging',
        '',
        'unicode: héllo wörld 🎉',
      ]) {
        final encoded = TomgCodec.encodeString(value);
        expect(TomgCodec.decodeString(encoded), equals(value));
      }
    });

    test('ciphertext never equals the plaintext for non-empty input', () {
      const value = 'secret';
      expect(TomgCodec.encodeString(value), isNot(equals(value)));
    });

    test('is deterministic: equal plaintext yields equal ciphertext', () {
      const value = 'https://api.us-east.example.com';
      expect(
        TomgCodec.encodeString(value),
        equals(TomgCodec.encodeString(value)),
      );
    });

    test('distinct plaintext yields distinct ciphertext', () {
      expect(
        TomgCodec.encodeString('us-east'),
        isNot(equals(TomgCodec.encodeString('eu-west'))),
      );
    });
  });

  group('TomgCodec.encodeInt / decodeInt', () {
    test('round-trips positive, negative, and zero', () {
      for (final value in <int>[0, 1, -1, 42, -42, 1 << 20, -(1 << 20)]) {
        expect(TomgCodec.decodeInt(TomgCodec.encodeInt(value)), equals(value));
      }
    });

    test('is deterministic', () {
      expect(TomgCodec.encodeInt(2025), equals(TomgCodec.encodeInt(2025)));
    });
  });

  group('TomgCodec.encodeDouble / decodeDouble', () {
    test('round-trips representative doubles', () {
      for (final value in <double>[
        0.0,
        -0.0,
        1.5,
        -1.5,
        3.14159,
        -0.0001,
        1e10,
        double.minPositive,
        double.maxFinite,
        double.infinity,
        double.negativeInfinity,
      ]) {
        final decoded = TomgCodec.decodeDouble(TomgCodec.encodeDouble(value));
        expect(_doubleBits(decoded), equals(_doubleBits(value)));
      }
    });

    test('round-trips a NaN payload bit for bit', () {
      final value = (ByteData(
        8,
      )..setUint64(0, 0x7ff8000000000001)).getFloat64(0);
      final decoded = TomgCodec.decodeDouble(TomgCodec.encodeDouble(value));
      expect(_doubleBits(decoded), equals(_doubleBits(value)));
    });

    test('is deterministic', () {
      expect(
        TomgCodec.encodeDouble(3.14),
        equals(TomgCodec.encodeDouble(3.14)),
      );
    });
  });

  group('.deobf extensions decode codec output', () {
    test('String.deobf reverses TomgCodec.encodeString', () {
      final ciphertext = TomgCodec.encodeString('secret');
      expect(ciphertext.deobf, equals('secret'));
    });

    test('int.deobf reverses TomgCodec.encodeInt', () {
      final ciphertext = TomgCodec.encodeInt(2025);
      expect(ciphertext.deobf, equals(2025));
    });

    test('double.deobf reverses TomgCodec.encodeDouble', () {
      final ciphertext = TomgCodec.encodeDouble(3.14);
      expect(ciphertext.deobf, equals(3.14));
    });
  });
}

int _doubleBits(double value) =>
    (ByteData(8)..setFloat64(0, value)).getUint64(0);

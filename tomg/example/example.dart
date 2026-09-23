// Standalone demo of tomg's runtime pieces. In a real project, `tomgen`
// generates the ciphertext literal and the `FeatureDeobf` companion class
// below from a TOML file at build time; here they're written by hand so
// this example runs with nothing but `dart run example/example.dart`.
//
// See https://pub.dev/packages/tomgen for the code generator, and
// https://github.com/ZackaryW/dart-tomg/tree/main/example for a full,
// generated, end-to-end example.
import 'package:tomg/tomg.dart';

// --- what you write ------------------------------------------------------

@TomgRegistry('feature.toml', key: 'id')
class Feature implements Obfuscated<FeatureDeobf> {
  const Feature({required this.id, @Obfus() required this.apiKey});

  final String id;

  @Obfus()
  final String apiKey;

  // The one line you write by hand: build_runner generators can only emit
  // top-level symbols into a part file, never a member of this class, so
  // `tomgen` generates `FeatureDeobf` but you declare this getter yourself.
  @override
  FeatureDeobf get deobf => FeatureDeobf(this);
}

// --- what `tomgen` would generate from feature.toml -----------------------
//
//   [beta]
//   id = "beta"
//   apiKey = "sk-demo-12345"
//
// tomgen encodes `apiKey` at build time; this example calls the same codec
// by hand so it runs without a build step.

class FeatureDeobf {
  const FeatureDeobf(this._o);

  final Feature _o;

  String get id => _o.id;

  String get apiKey => _o.apiKey.deobf;
}

void main() {
  final feature = Feature(
    id: 'beta',
    // Stand-in for tomgen's generated ciphertext literal.
    apiKey: TomgCodec.encodeString('sk-demo-12345'),
  );

  print('stored (ciphertext): ${feature.apiKey}');
  print('decoded (runtime):   ${feature.deobf.apiKey}');
  assert(feature.deobf.apiKey == 'sk-demo-12345');
}

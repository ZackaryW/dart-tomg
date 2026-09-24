import 'dart:io';
import 'dart:isolate';

import 'package:dart_tomg_example/generated/api_endpoints.dart';
import 'package:test/test.dart';
import 'package:tomg/tomg.dart';

void main() {
  test('generates a keyed registry from external TOML', () {
    expect(apiEndpointRegistry, hasLength(3));
    expect(
      apiEndpointRegistry.keys,
      containsAll(<String>[
        TomgCodec.encodeString('code-us'),
        TomgCodec.encodeString('code-eu'),
        TomgCodec.encodeString('code-stage'),
      ]),
    );
    expect(apiEndpointRegistry, isNot(contains('__tomg')));
    expect(
      apiEndpointRegistry[TomgCodec.encodeString('code-us')]!.deobf.id,
      'code-us',
    );
    expect(apiEndpointRegistry[TomgCodec.encodeString('unknown')], isNull);
  });

  test('uses constructor defaults for omitted fields', () {
    final endpoint = apiEndpointRegistry[TomgCodec.encodeString('code-us')]!;
    expect(endpoint.visible, isTrue);
    expect(endpoint.enabled, isTrue);
  });

  test('embeds an environment fallback at generation time', () {
    expect(
      apiEndpointRegistry[TomgCodec.encodeString('code-us')]!.environment,
      'production',
    );
    expect(
      apiEndpointRegistry[TomgCodec.encodeString('code-stage')]!.environment,
      'staging',
    );
  });

  test('stores an obfuscated field as ciphertext and decodes it', () {
    final endpoint = apiEndpointRegistry[TomgCodec.encodeString('code-us')]!;
    expect(endpoint, isA<Obfuscated<ApiEndpointDeobf>>());
    expect(endpoint.url, isNot('https://api.us-east.example.com'));
    expect(endpoint.deobf.url, 'https://api.us-east.example.com');
  });

  test('generated source does not contain obfuscated plaintext', () {
    final generatedUri = Isolate.resolvePackageUriSync(
      Uri.parse('package:dart_tomg_example/generated/api_endpoints.g.dart'),
    )!;
    final generated = File.fromUri(generatedUri).readAsStringSync();
    expect(generated, isNot(contains('https://api.us-east.example.com')));
    expect(generated, isNot(contains('https://api.eu-west.example.com')));
    expect(generated, isNot(contains('https://staging.example.com')));
    expect(generated, isNot(contains('"code-us"')));
    expect(generated, isNot(contains('"code-eu"')));
    expect(generated, isNot(contains('"code-stage"')));
    expect(generated, isNot(contains('primary-us')));
    expect(generated, isNot(contains('primary-eu')));
    expect(generated, isNot(contains('preview')));

    final modelUri = Isolate.resolvePackageUriSync(
      Uri.parse('package:dart_tomg_example/generated/api_endpoints.dart'),
    )!;
    final model = File.fromUri(modelUri).readAsStringSync();
    expect(model, contains('@Obfus() required this.id'));
  });
}

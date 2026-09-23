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
      containsAll(<String>['us-east', 'eu-west', 'staging']),
    );
    expect(apiEndpointRegistry, isNot(contains('__tomg')));
  });

  test('uses constructor defaults for omitted fields', () {
    final endpoint = apiEndpointRegistry['us-east']!;
    expect(endpoint.visible, isTrue);
    expect(endpoint.enabled, isTrue);
  });

  test('embeds an environment fallback at generation time', () {
    expect(apiEndpointRegistry['us-east']!.environment, 'production');
    expect(apiEndpointRegistry['staging']!.environment, 'staging');
  });

  test('stores an obfuscated field as ciphertext and decodes it', () {
    final endpoint = apiEndpointRegistry['us-east']!;
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
  });
}

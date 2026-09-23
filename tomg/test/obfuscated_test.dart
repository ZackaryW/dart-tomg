import 'package:test/test.dart';
import 'package:tomg/tomg.dart';

class _Endpoint implements Obfuscated<_EndpointDeobf> {
  const _Endpoint({required this.id, required this.url});

  final String id;

  @Obfus()
  final String url;

  @override
  _EndpointDeobf get deobf => _EndpointDeobf(this);
}

class _EndpointDeobf {
  const _EndpointDeobf(this._o);

  final _Endpoint _o;

  String get id => _o.id;

  String get url => _o.url.deobf;
}

void main() {
  test('a hand-written companion satisfies Obfuscated<D>', () {
    final encodedUrl = TomgCodec.encodeString(
      'https://api.us-east.example.com',
    );
    const id = 'us-east';
    final endpoint = _Endpoint(id: id, url: encodedUrl);

    expect(endpoint, isA<Obfuscated<_EndpointDeobf>>());
    expect(endpoint.url, equals(encodedUrl));
    expect(endpoint.deobf.url, equals('https://api.us-east.example.com'));
    expect(endpoint.deobf.id, equals(id));
  });
}

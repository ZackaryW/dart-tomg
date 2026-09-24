import 'package:test/test.dart';
import 'package:tomg/tomg.dart';

void main() {
  test('TomgRegistry keeps digest optional and exposes a supplied pin', () {
    const local = TomgRegistry('config.toml', key: 'id');
    const external = TomgRegistry(
      '../../config/items.toml',
      key: 'id',
      digest:
          'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );

    expect(local.digest, isNull);
    expect(external.digest, startsWith('sha256:'));
  });
}

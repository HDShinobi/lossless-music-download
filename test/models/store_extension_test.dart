import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/store_extension.dart';

void main() {
  group('StoreExtension.fromRegistryJson', () {
    test('parses min_app_version (snake_case)', () {
      final e = StoreExtension.fromRegistryJson(
        {'id': 'amazon', 'version': '2.2.0', 'min_app_version': '4.7.0'},
        'Community',
      );
      expect(e.minAppVersion, '4.7.0');
    });

    test('parses minAppVersion (camelCase) fallback', () {
      final e = StoreExtension.fromRegistryJson(
        {'id': 'x', 'version': '1.0.0', 'minAppVersion': '4.3.0'},
        'Community',
      );
      expect(e.minAppVersion, '4.3.0');
    });

    test('minAppVersion is null when absent', () {
      final e = StoreExtension.fromRegistryJson(
        {'id': 'x', 'version': '1.0.0'},
        'Community',
      );
      expect(e.minAppVersion, isNull);
    });
  });
}

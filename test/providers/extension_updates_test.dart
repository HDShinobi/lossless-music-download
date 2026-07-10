import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/models/store_extension.dart';
import 'package:lossless_music_download/providers/extension_updates_provider.dart';

InstalledExtension _installed(String id, String version) => InstalledExtension(
      id: id,
      name: id,
      version: version,
      enabled: true,
      types: const ['download'],
      displayName: id,
      description: '',
      status: 'ready',
      permissions: const [],
      hasMetadataProvider: false,
      hasDownloadProvider: true,
      hasLyricsProvider: false,
    );

StoreExtension _store(String id, String version, {String? minApp}) =>
    StoreExtension(
      id: id,
      displayName: id,
      version: version,
      description: '',
      category: 'download',
      downloadUrl: 'https://example/$id.sflx',
      sourceName: 'Community',
      minAppVersion: minApp,
    );

void main() {
  group('computeExtensionUpdates', () {
    test('flags an installed extension with a newer catalog version', () {
      final updates = computeExtensionUpdates(
        [_installed('amazon', '2.1.0')],
        [_store('amazon', '2.2.0')],
        '0.5.0',
      );
      expect(updates, hasLength(1));
      expect(updates.single.id, 'amazon');
      expect(updates.single.fromVersion, '2.1.0');
      expect(updates.single.toVersion, '2.2.0');
      expect(updates.single.compatible, isTrue);
    });

    test('no update when installed is equal or newer', () {
      expect(
        computeExtensionUpdates(
            [_installed('a', '1.2.0')], [_store('a', '1.2.0')], '0.5.0'),
        isEmpty,
      );
      expect(
        computeExtensionUpdates(
            [_installed('a', '1.3.0')], [_store('a', '1.2.0')], '0.5.0'),
        isEmpty,
      );
    });

    test('marks incompatible when min_app_version exceeds app version', () {
      final updates = computeExtensionUpdates(
        [_installed('qobuz', '1.0.0')],
        [_store('qobuz', '1.1.0', minApp: '9.9.0')],
        '0.5.0',
      );
      expect(updates.single.compatible, isFalse);
      expect(compatibleUpdateCount(updates), 0);
    });

    test('ignores catalog entries that are not installed', () {
      expect(
        computeExtensionUpdates(
            const [], [_store('deezer', '1.2.0')], '0.5.0'),
        isEmpty,
      );
    });

    test('treats unknown app version as compatible (not-yet-loaded)', () {
      final updates = computeExtensionUpdates(
        [_installed('q', '1.0.0')],
        [_store('q', '1.1.0', minApp: '9.9.0')],
        '',
      );
      expect(updates.single.compatible, isTrue);
    });

    test('compatibleUpdateCount counts only compatible updates', () {
      final updates = computeExtensionUpdates(
        [_installed('a', '1.0.0'), _installed('b', '1.0.0')],
        [_store('a', '2.0.0'), _store('b', '2.0.0', minApp: '9.0.0')],
        '0.5.0',
      );
      expect(updates, hasLength(2));
      expect(compatibleUpdateCount(updates), 1);
    });
  });
}

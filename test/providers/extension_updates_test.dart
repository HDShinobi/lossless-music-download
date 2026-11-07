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
      );
      expect(updates, hasLength(1));
      expect(updates.single.id, 'amazon');
      expect(updates.single.fromVersion, '2.1.0');
      expect(updates.single.toVersion, '2.2.0');
    });

    test('no update when installed is equal or newer', () {
      expect(
        computeExtensionUpdates(
            [_installed('a', '1.2.0')], [_store('a', '1.2.0')]),
        isEmpty,
      );
      expect(
        computeExtensionUpdates(
            [_installed('a', '1.3.0')], [_store('a', '1.2.0')]),
        isEmpty,
      );
    });

    test('skips updates requiring a newer engine', () {
      expect(
        computeExtensionUpdates(
          [_installed('qobuz', '1.0.0')],
          [_store('qobuz', '1.1.0', minApp: '5.3.2')],
        ),
        isEmpty,
      );
    });

    for (final minimum in ['5.3.1', '5.3.0', null]) {
      test('allows updates with minimum engine $minimum', () {
        final updates = computeExtensionUpdates(
          [_installed('qobuz', '1.0.0')],
          [_store('qobuz', '1.1.0', minApp: minimum)],
        );
        expect(updates, hasLength(1));
        expect(updates.single.toVersion, '1.1.0');
      });
    }

    test('uses the supplied engine version for compatibility', () {
      final installed = [_installed('qobuz', '1.0.0')];
      final catalog = [_store('qobuz', '1.1.0', minApp: '5.4.0')];
      expect(
        computeExtensionUpdates(installed, catalog, engineVersion: '5.3.9'),
        isEmpty,
      );
      expect(
        computeExtensionUpdates(installed, catalog, engineVersion: '5.4.0'),
        hasLength(1),
      );
    });

    test('ignores catalog entries that are not installed', () {
      expect(
        computeExtensionUpdates(const [], [_store('deezer', '1.2.0')]),
        isEmpty,
      );
    });
  });
}

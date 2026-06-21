import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';

// ---------------------------------------------------------------------------
// Fake bridge — subclasses BackendBridge and overrides only the methods used
// by ExtensionsController. No real MethodChannel calls are made.
// ---------------------------------------------------------------------------
class FakeBackendBridge extends BackendBridge {
  final List<InstalledExtension> _extensions;
  final List<String> initCalls = [];
  final List<String> loadDirCalls = [];
  final List<(String, bool)> setEnabledCalls = [];
  final List<String> removeCalls = [];

  FakeBackendBridge(this._extensions);

  @override
  Future<void> initExtensionSystem(String extDir, String dataDir) async {
    initCalls.add('$extDir|$dataDir');
  }

  @override
  Future<String?> loadExtensionsFromDir(String dirPath) async {
    loadDirCalls.add(dirPath);
    return null;
  }

  @override
  Future<List<InstalledExtension>> getInstalledExtensions() async {
    return List.unmodifiable(_extensions);
  }

  @override
  Future<void> setExtensionEnabled(String id, bool enabled) async {
    setEnabledCalls.add((id, enabled));
    final i = _extensions.indexWhere((e) => e.id == id);
    if (i != -1) {
      _extensions[i] = InstalledExtension(
        id: _extensions[i].id,
        name: _extensions[i].name,
        version: _extensions[i].version,
        displayName: _extensions[i].displayName,
        description: _extensions[i].description,
        status: _extensions[i].status,
        iconPath: _extensions[i].iconPath,
        enabled: enabled,
        types: _extensions[i].types,
        permissions: _extensions[i].permissions,
        hasMetadataProvider: _extensions[i].hasMetadataProvider,
        hasDownloadProvider: _extensions[i].hasDownloadProvider,
        hasLyricsProvider: _extensions[i].hasLyricsProvider,
      );
    }
  }

  @override
  Future<void> removeExtension(String id) async {
    removeCalls.add(id);
    _extensions.removeWhere((e) => e.id == id);
  }
}

// ---------------------------------------------------------------------------
// Helper: create a fake extension
// ---------------------------------------------------------------------------
InstalledExtension _fakeExt({
  required String id,
  bool enabled = true,
}) =>
    InstalledExtension(
      id: id,
      name: id,
      displayName: id,
      version: '1.0.0',
      description: '',
      status: 'active',
      enabled: enabled,
      types: const [],
      permissions: const [],
      hasMetadataProvider: false,
      hasDownloadProvider: false,
      hasLyricsProvider: false,
    );

// ---------------------------------------------------------------------------
// Helper: build a ProviderContainer with both bridge and dirs overridden
// ---------------------------------------------------------------------------
ProviderContainer _makeContainer(FakeBackendBridge fake) {
  return ProviderContainer(
    overrides: [
      backendBridgeProvider.overrideWithValue(fake),
      // Provide a plain string tuple — no path_provider call needed
      appDirsProvider.overrideWithValue(
        Future.value(('/fake/extensions', '/fake/ext_data')),
      ),
    ],
  );
}

void main() {
  group('extensionsProvider', () {
    test('resolves to fake list on init', () async {
      final fake = FakeBackendBridge([
        _fakeExt(id: 'deezer'),
        _fakeExt(id: 'tidal'),
      ]);
      final container = _makeContainer(fake);
      addTearDown(container.dispose);

      final result = await container.read(extensionsProvider.future);

      expect(result.map((e) => e.id), containsAll(['deezer', 'tidal']));
      expect(fake.initCalls, hasLength(1));
      expect(fake.initCalls.first, '/fake/extensions|/fake/ext_data');
    });

    // Regression: build() must load persisted extensions from disk after init,
    // otherwise extensions installed in a previous session vanish on restart
    // (banner shows "0 sources", search finds nothing).
    test('build loads extensions from the extensions dir after init', () async {
      final fake = FakeBackendBridge([_fakeExt(id: 'deezer')]);
      final container = _makeContainer(fake);
      addTearDown(container.dispose);

      await container.read(extensionsProvider.future);

      expect(fake.loadDirCalls, ['/fake/extensions'],
          reason: 'loadExtensionsFromDir must run on the extensions dir at startup');
    });

    test('setEnabled calls bridge and refreshes state', () async {
      final fake = FakeBackendBridge([
        _fakeExt(id: 'deezer', enabled: true),
      ]);
      final container = _makeContainer(fake);
      addTearDown(container.dispose);

      // Wait for initial load
      await container.read(extensionsProvider.future);

      // Disable deezer
      await container.read(extensionsProvider.notifier).setEnabled('deezer', false);

      final after = await container.read(extensionsProvider.future);
      expect(fake.setEnabledCalls, [('deezer', false)]);
      expect(after.single.enabled, isFalse);
    });

    test('remove drops the extension', () async {
      final fake = FakeBackendBridge([
        _fakeExt(id: 'deezer'),
        _fakeExt(id: 'tidal'),
      ]);
      final container = _makeContainer(fake);
      addTearDown(container.dispose);

      await container.read(extensionsProvider.future);

      await container.read(extensionsProvider.notifier).remove('deezer');

      final after = await container.read(extensionsProvider.future);
      expect(fake.removeCalls, ['deezer']);
      expect(after.map((e) => e.id), ['tidal']);
      expect(after.any((e) => e.id == 'deezer'), isFalse);
    });

    test('refresh re-fetches without re-calling initExtensionSystem', () async {
      final fake = FakeBackendBridge([_fakeExt(id: 'a')]);
      final container = _makeContainer(fake);
      addTearDown(container.dispose);

      await container.read(extensionsProvider.future);
      expect(fake.initCalls, hasLength(1));

      await container.read(extensionsProvider.notifier).refresh();
      // init should NOT be called again on refresh
      expect(fake.initCalls, hasLength(1));

      final after = await container.read(extensionsProvider.future);
      expect(after.single.id, 'a');
    });
  });
}

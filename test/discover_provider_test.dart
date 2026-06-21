import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/models/store_extension.dart';
import 'package:lossless_music_download/providers/discover_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:lossless_music_download/services/extension_registry_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fake registry service — subclasses ExtensionRegistryService (which takes
// an http.Client in its ctor). We pass a dummy client and override both
// network methods so no real I/O happens.
// ---------------------------------------------------------------------------
class _FakeRegistryService extends ExtensionRegistryService {
  final List<StoreExtension> _catalog;
  final Map<String, String> _downloadPaths;
  final List<String> downloadCalls = [];

  _FakeRegistryService.withData({
    List<StoreExtension> catalog = const [],
    Map<String, String> downloadPaths = const {},
  })  : _catalog = catalog,
        _downloadPaths = downloadPaths,
        super(http.Client());

  @override
  Future<List<StoreExtension>> fetchCatalog(String aggregatorUrl) async =>
      List.unmodifiable(_catalog);

  @override
  Future<String> downloadExtension(StoreExtension e, String destDir) async {
    downloadCalls.add(e.id);
    return _downloadPaths[e.id] ?? '/fake/_dl/${e.id}.spotiflac-ext';
  }
}

// ---------------------------------------------------------------------------
// Fake bridge — records installExtension calls, no real MethodChannel.
// ---------------------------------------------------------------------------
class _FakeBackendBridge extends BackendBridge {
  final List<String> installCalls = [];
  final List<(String, bool)> enabledCalls = [];
  final List<InstalledExtension> _extensions;

  /// JSON returned by installExtension (mimics the backend payload with `id`).
  final String? installResult;

  _FakeBackendBridge({this.installResult}) : _extensions = const [];

  @override
  Future<void> initExtensionSystem(String extDir, String dataDir) async {}

  @override
  Future<String?> loadExtensionsFromDir(String dirPath) async => null;

  @override
  Future<String?> installExtension(String path) async {
    installCalls.add(path);
    return installResult;
  }

  @override
  Future<void> setExtensionEnabled(String id, bool enabled) async {
    enabledCalls.add((id, enabled));
  }

  @override
  Future<List<InstalledExtension>> getInstalledExtensions() async =>
      List.unmodifiable(_extensions);
}

// ---------------------------------------------------------------------------
// Helper to build StoreExtension fixtures
// ---------------------------------------------------------------------------
StoreExtension _fakeStoreExt(String id) => StoreExtension(
      id: id,
      displayName: id,
      version: '1.0.0',
      description: 'desc',
      category: 'utility',
      downloadUrl: 'https://example.com/$id.spotiflac-ext',
      sourceName: 'test-registry',
    );

// ---------------------------------------------------------------------------
// Helper: container with all external deps overridden (hermetic)
// ---------------------------------------------------------------------------
ProviderContainer _makeContainer({
  required _FakeRegistryService registryService,
  BackendBridge? bridge,
  String extDir = '/fake/ext',
}) {
  return ProviderContainer(
    overrides: [
      registryServiceProvider.overrideWithValue(registryService),
      backendBridgeProvider.overrideWithValue(bridge ?? _FakeBackendBridge()),
      appDirsProvider.overrideWithValue(
        Future.value((extDir, '/fake/data')),
      ),
    ],
  );
}

void main() {
  // Required for shared_preferences and other platform channels in unit tests.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('discoverProvider', () {
    test('resolves to the catalog returned by fake service', () async {
      final svc = _FakeRegistryService.withData(
        catalog: [_fakeStoreExt('deezer'), _fakeStoreExt('tidal')],
      );
      final container = _makeContainer(registryService: svc);
      addTearDown(container.dispose);

      final result = await container.read(discoverProvider.future);

      expect(result.map((e) => e.id), containsAll(['deezer', 'tidal']));
      expect(result, hasLength(2));
    });

    test('resolves to empty list when catalog is empty', () async {
      final svc = _FakeRegistryService.withData(catalog: []);
      final container = _makeContainer(registryService: svc);
      addTearDown(container.dispose);

      final result = await container.read(discoverProvider.future);

      expect(result, isEmpty);
    });

    test('install: calls bridge.installExtension with downloaded path', () async {
      final extDir = Directory.systemTemp.createTempSync('discover_test_').path;
      addTearDown(() => Directory(extDir).deleteSync(recursive: true));

      final ext = _fakeStoreExt('deezer');
      final expectedPath = '$extDir/_dl/deezer.spotiflac-ext';
      final svc = _FakeRegistryService.withData(
        catalog: [ext],
        downloadPaths: {'deezer': expectedPath},
      );
      final bridge = _FakeBackendBridge();
      final container = _makeContainer(
        registryService: svc,
        bridge: bridge,
        extDir: extDir,
      );
      addTearDown(container.dispose);

      // Wait for initial build
      await container.read(discoverProvider.future);

      // Act
      await container.read(discoverProvider.notifier).install(ext);

      // Assert: bridge received the correct path
      expect(bridge.installCalls, hasLength(1));
      expect(bridge.installCalls.single, expectedPath);
      // Assert: service downloadExtension was called with correct extension id
      expect(svc.downloadCalls, ['deezer']);
    });

    // Regression: the backend installs extensions DISABLED by default; install()
    // must auto-enable so the source is usable without a second manual toggle.
    test('install: auto-enables the extension using the backend id', () async {
      final extDir = Directory.systemTemp.createTempSync('discover_enable_').path;
      addTearDown(() => Directory(extDir).deleteSync(recursive: true));

      final ext = _fakeStoreExt('deezer');
      final svc = _FakeRegistryService.withData(
        catalog: [ext],
        downloadPaths: {'deezer': '$extDir/_dl/deezer.spotiflac-ext'},
      );
      // Backend returns the authoritative manifest id in its install payload.
      final bridge = _FakeBackendBridge(
        installResult: '{"id":"deezer","enabled":false}',
      );
      final container = _makeContainer(
        registryService: svc,
        bridge: bridge,
        extDir: extDir,
      );
      addTearDown(container.dispose);

      await container.read(discoverProvider.future);
      await container.read(discoverProvider.notifier).install(ext);

      expect(bridge.enabledCalls, [('deezer', true)],
          reason: 'install must enable the freshly installed extension');
    });

    // Falls back to the StoreExtension id when the install payload has no id.
    test('install: auto-enables via store id when payload lacks an id', () async {
      final extDir = Directory.systemTemp.createTempSync('discover_enable2_').path;
      addTearDown(() => Directory(extDir).deleteSync(recursive: true));

      final ext = _fakeStoreExt('tidal');
      final svc = _FakeRegistryService.withData(
        catalog: [ext],
        downloadPaths: {'tidal': '$extDir/_dl/tidal.spotiflac-ext'},
      );
      final bridge = _FakeBackendBridge(); // installResult == null
      final container = _makeContainer(
        registryService: svc,
        bridge: bridge,
        extDir: extDir,
      );
      addTearDown(container.dispose);

      await container.read(discoverProvider.future);
      await container.read(discoverProvider.notifier).install(ext);

      expect(bridge.enabledCalls, [('tidal', true)]);
    });

    test('install: extensionsProvider is invalidated (re-reads bridge)', () async {
      final extDir = Directory.systemTemp.createTempSync('discover_inv_').path;
      addTearDown(() => Directory(extDir).deleteSync(recursive: true));

      final ext = _fakeStoreExt('deezer');
      final installedExt = InstalledExtension(
        id: 'deezer',
        name: 'deezer',
        displayName: 'Deezer',
        version: '1.0.0',
        description: '',
        status: 'active',
        enabled: true,
        types: const [],
        permissions: const [],
        hasMetadataProvider: false,
        hasDownloadProvider: true,
        hasLyricsProvider: false,
      );

      int getInstalledCallCount = 0;
      final bridge = _FakeBackendBridgeWithCounter(
        onGetInstalled: () {
          getInstalledCallCount++;
          return [installedExt];
        },
      );
      final svc = _FakeRegistryService.withData(
        catalog: [ext],
        downloadPaths: {'deezer': '$extDir/_dl/deezer.spotiflac-ext'},
      );
      final container = _makeContainer(
        registryService: svc,
        bridge: bridge,
        extDir: extDir,
      );
      addTearDown(container.dispose);

      // Trigger initial load of extensionsProvider to establish a subscription
      await container.read(extensionsProvider.future);
      final beforeCount = getInstalledCallCount;

      // Act
      await container.read(discoverProvider.notifier).install(ext);

      // extensionsProvider was invalidated, so reading it again causes a refetch
      await container.read(extensionsProvider.future);

      expect(getInstalledCallCount, greaterThan(beforeCount),
          reason: 'extensionsProvider should refetch after invalidation');
    });

    test('setAggregatorUrl updates the aggregatorUrlProvider', () async {
      SharedPreferences.setMockInitialValues({});
      const newUrl = 'https://example.com/custom-registry.json';
      final svc = _FakeRegistryService.withData(catalog: []);
      final container = _makeContainer(registryService: svc);
      addTearDown(container.dispose);

      await container.read(discoverProvider.future);

      await container.read(discoverProvider.notifier).setAggregatorUrl(newUrl);

      // The aggregatorUrlProvider should now reflect the new URL
      final url = container.read(aggregatorUrlProvider);
      expect(url, newUrl);
    });
  });

  group('aggregatorUrlProvider', () {
    test('initial state is kDefaultAggregatorUrl', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final url = container.read(aggregatorUrlProvider);
      expect(url, kDefaultAggregatorUrl);
    });
  });
}

// ---------------------------------------------------------------------------
// Variant fake bridge that tracks getInstalledExtensions call counts
// ---------------------------------------------------------------------------
class _FakeBackendBridgeWithCounter extends BackendBridge {
  final List<InstalledExtension> Function() onGetInstalled;
  final List<String> installCalls = [];

  _FakeBackendBridgeWithCounter({required this.onGetInstalled});

  @override
  Future<void> initExtensionSystem(String extDir, String dataDir) async {}

  @override
  Future<String?> loadExtensionsFromDir(String dirPath) async => null;

  @override
  Future<String?> installExtension(String path) async {
    installCalls.add(path);
    return null;
  }

  @override
  Future<void> setExtensionEnabled(String id, bool enabled) async {}

  @override
  Future<List<InstalledExtension>> getInstalledExtensions() async =>
      onGetInstalled();
}

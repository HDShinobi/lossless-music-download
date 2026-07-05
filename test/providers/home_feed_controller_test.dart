import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/home_feed_provider.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _ext1 = InstalledExtension(
  id: 'ext1',
  name: 'Ext1',
  version: '1.0',
  enabled: true,
  types: const [],
  displayName: 'Ext1',
  description: '',
  status: 'active',
  permissions: const [],
  hasMetadataProvider: false,
  hasDownloadProvider: false,
  hasLyricsProvider: false,
  capabilities: const {'homeFeed': true},
);

final _ext2 = InstalledExtension(
  id: 'ext2',
  name: 'Ext2',
  version: '1.0',
  enabled: true,
  types: const [],
  displayName: 'Ext2',
  description: '',
  status: 'active',
  permissions: const [],
  hasMetadataProvider: false,
  hasDownloadProvider: false,
  hasLyricsProvider: false,
  capabilities: const {'homeFeed': true},
);

Map<String, dynamic> _envelope(String title) => {
      'success': true,
      'sections': [
        {
          'title': title,
          'items': [
            {'id': 't1', 'type': 'track', 'name': 'Song A'},
          ],
        },
      ],
    };

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeBridge extends BackendBridge {
  int homeFeedCalls = 0;
  Map<String, dynamic>? envelope;
  bool throwOnFetch = false;

  @override
  Future<Map<String, dynamic>?> getExtensionHomeFeed(
      String extensionId) async {
    homeFeedCalls++;
    if (throwOnFetch) throw Exception('fetch failed');
    return envelope;
  }
}

// Minimal AsyncNotifier that returns a fixed list without touching any
// channel. Must extend ExtensionsController so overrideWith is type-safe.
class _FakeExtensionsController extends ExtensionsController {
  final List<InstalledExtension> _exts;
  _FakeExtensionsController(this._exts);

  @override
  Future<List<InstalledExtension>> build() async => _exts;
}

// Fixed source notifier — skips the persisted-value microtask entirely so
// tests don't race against a SharedPreferences load.
class _FixedHomeFeedSourceNotifier extends HomeFeedSourceNotifier {
  final String? _value;
  _FixedHomeFeedSourceNotifier(this._value);

  @override
  String? build() => _value;
}

ProviderContainer _makeContainer({
  required _FakeBridge bridge,
  List<InstalledExtension> exts = const [],
  String? source,
}) {
  return ProviderContainer(overrides: [
    backendBridgeProvider.overrideWithValue(bridge),
    extensionsProvider.overrideWith(() => _FakeExtensionsController(exts)),
    homeFeedSourceProvider
        .overrideWith(() => _FixedHomeFeedSourceNotifier(source)),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HomeFeedController', () {
    test(
        'resolves the first enabled hasHomeFeed extension when source is '
        'null, fetches, and yields parsed sections', () async {
      final bridge = _FakeBridge()..envelope = _envelope('Trending');
      final container = _makeContainer(bridge: bridge, exts: [_ext1]);
      addTearDown(container.dispose);

      final result = await container.read(homeFeedControllerProvider.future);

      expect(result, hasLength(1));
      expect(result.first.title, 'Trending');
      expect(bridge.homeFeedCalls, 1);
    });

    test('source __off__ yields [] and never calls the bridge', () async {
      final bridge = _FakeBridge()..envelope = _envelope('Trending');
      final container = _makeContainer(
        bridge: bridge,
        exts: [_ext1],
        source: homeFeedSourceOff,
      );
      addTearDown(container.dispose);

      final result = await container.read(homeFeedControllerProvider.future);

      expect(result, isEmpty);
      expect(bridge.homeFeedCalls, 0);
    });

    test(
        'source is a specific id not present/enabled falls back to auto '
        '(first capable extension) and calls the bridge', () async {
      final bridge = _FakeBridge()..envelope = _envelope('Trending');
      final container = _makeContainer(
        bridge: bridge,
        exts: [_ext1],
        source: 'nonexistent-ext',
      );
      addTearDown(container.dispose);

      final result = await container.read(homeFeedControllerProvider.future);

      expect(result, hasLength(1));
      expect(result.first.title, 'Trending');
      expect(bridge.homeFeedCalls, 1);
    });

    test(
        'source is a stale specific id with no capable extensions at all '
        'yields [] and never calls the bridge', () async {
      final bridge = _FakeBridge()..envelope = _envelope('Trending');
      final container = _makeContainer(
        bridge: bridge,
        exts: const [],
        source: 'nonexistent-ext',
      );
      addTearDown(container.dispose);

      final result = await container.read(homeFeedControllerProvider.future);

      expect(result, isEmpty);
      expect(bridge.homeFeedCalls, 0);
    });

    test(
        'fresh cache (within TTL) returns cached sections without calling '
        'the bridge', () async {
      SharedPreferences.setMockInitialValues({
        'home_feed_cache_ext1': jsonEncode(_envelope('Cached')),
        'home_feed_cache_ts_ext1': DateTime.now().millisecondsSinceEpoch,
      });
      final bridge = _FakeBridge()..throwOnFetch = true;
      final container = _makeContainer(bridge: bridge, exts: [_ext1]);
      addTearDown(container.dispose);

      final result = await container.read(homeFeedControllerProvider.future);

      expect(result, hasLength(1));
      expect(result.first.title, 'Cached');
      expect(bridge.homeFeedCalls, 0);
    });

    test(
        'cache is scoped per extension id — switching source does not leak '
        'the previous extension\'s cached sections', () async {
      // ext1's cache is fresh; ext2 has no cache at all.
      SharedPreferences.setMockInitialValues({
        'home_feed_cache_ext1': jsonEncode(_envelope('Ext1 Cached')),
        'home_feed_cache_ts_ext1': DateTime.now().millisecondsSinceEpoch,
      });
      final bridge = _FakeBridge()..envelope = _envelope('Ext2 Fresh');
      final container = _makeContainer(
        bridge: bridge,
        exts: [_ext1, _ext2],
        source: _ext1.id,
      );
      addTearDown(container.dispose);

      final first = await container.read(homeFeedControllerProvider.future);
      expect(first.first.title, 'Ext1 Cached');
      expect(bridge.homeFeedCalls, 0);

      // Switch the source to ext2 — it has no cache under its own key, so
      // it must fetch fresh data instead of returning ext1's stale cache.
      await container.read(homeFeedSourceProvider.notifier).set(_ext2.id);
      final second = await container.read(homeFeedControllerProvider.future);

      expect(second.first.title, 'Ext2 Fresh');
      expect(bridge.homeFeedCalls, 1);
    });

    test('refresh() forces a bridge call even with fresh cache', () async {
      SharedPreferences.setMockInitialValues({
        'home_feed_cache_ext1': jsonEncode(_envelope('Cached')),
        'home_feed_cache_ts_ext1': DateTime.now().millisecondsSinceEpoch,
      });
      final bridge = _FakeBridge()..envelope = _envelope('Refreshed');
      final container = _makeContainer(bridge: bridge, exts: [_ext1]);
      addTearDown(container.dispose);

      final initial = await container.read(homeFeedControllerProvider.future);
      expect(initial.first.title, 'Cached');
      expect(bridge.homeFeedCalls, 0);

      await container.read(homeFeedControllerProvider.notifier).refresh();

      expect(bridge.homeFeedCalls, 1);
      final after = container.read(homeFeedControllerProvider).value;
      expect(after, isNotNull);
      expect(after!.first.title, 'Refreshed');
    });

    test(
        'refresh() keeps the previously-visible sections when the forced '
        'fetch throws (does not wipe the feed to [])', () async {
      final bridge = _FakeBridge()..envelope = _envelope('Trending');
      final container = _makeContainer(bridge: bridge, exts: [_ext1]);
      addTearDown(container.dispose);

      final initial = await container.read(homeFeedControllerProvider.future);
      expect(initial, hasLength(1));
      expect(initial.first.title, 'Trending');

      bridge.throwOnFetch = true;
      await container.read(homeFeedControllerProvider.notifier).refresh();

      final after = container.read(homeFeedControllerProvider).value;
      expect(after, isNotNull);
      expect(after, hasLength(1));
      expect(after!.first.title, 'Trending');
    });
  });
}

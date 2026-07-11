import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/search_provider.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bridge whose per-provider entity search returns album/artist maps that do
/// NOT echo a `provider_id`/`source` (like several real extensions), to prove
/// the search layer stamps the queried provider itself.
class _FakeBridge extends BackendBridge {
  @override
  Future<List<Track>> searchTracks(String query,
          {int limit = 20, bool includeExtensions = true}) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> getSearchProviders() async => [
        {'id': 'deezer'},
      ];

  @override
  Future<List<Map<String, dynamic>>> customSearch(String extensionId,
      String query, {Map<String, dynamic>? options}) async {
    final filter = options?['filter'];
    if (filter == 'album') {
      // No provider_id / source echoed by the extension.
      return [
        {'id': '12345', 'name': 'Discovery', 'artists': 'Daft Punk'},
      ];
    }
    return const [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'album entity result is tagged with the queried provider even when the '
      'extension omits provider_id (routeId => provider:id, not a bare id)',
      () async {
    final container = ProviderContainer(overrides: [
      backendBridgeProvider.overrideWithValue(_FakeBridge()),
    ]);
    addTearDown(container.dispose);

    await container.read(searchProvider.notifier).search('discovery');

    final results = container.read(searchProvider).value!;
    expect(results.albums, hasLength(1));
    // Must be resolvable through the provider metadata path, not misrouted to
    // Spotify's bare-id handleUrl fallback.
    expect(results.albums.single.routeId, 'deezer:12345');
  });
}

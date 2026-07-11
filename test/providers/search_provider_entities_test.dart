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
    // PA2: the app queries WITHOUT a type filter and buckets by item_type.
    // Return a mix of entity types; the album omits provider_id/source so the
    // stamping is also exercised.
    return [
      {'id': 't1', 'name': 'Track', 'item_type': 'track'},
      {'id': '12345', 'name': 'Discovery', 'artists': 'Daft Punk',
        'item_type': 'album'},
      {'id': 'a9', 'name': 'Daft Punk', 'item_type': 'artist',
        'provider_id': 'deezer'},
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'unfiltered entity search buckets by item_type and stamps the provider',
      () async {
    final container = ProviderContainer(overrides: [
      backendBridgeProvider.overrideWithValue(_FakeBridge()),
    ]);
    addTearDown(container.dispose);

    await container.read(searchProvider.notifier).search('discovery');

    final results = container.read(searchProvider).value!;
    // The track item must NOT leak into the album/artist sections.
    expect(results.albums, hasLength(1));
    expect(results.artists, hasLength(1));
    // Album omitted provider_id → stamped with the queried provider, so it
    // resolves via getProviderMetadata, not the Spotify bare-id fallback.
    expect(results.albums.single.routeId, 'deezer:12345');
    expect(results.artists.single.routeId, 'deezer:a9');
  });
}

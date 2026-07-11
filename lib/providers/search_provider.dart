import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/search_entities.dart';
import '../models/track.dart';
import '../services/backend_bridge.dart';
import 'extensions_provider.dart';
import 'recent_searches_provider.dart';

class SearchNotifier extends AsyncNotifier<SearchResults> {
  /// Bumped on every search so a slow entity (phase 2) result from an earlier
  /// query can't overwrite a newer search.
  int _seq = 0;

  @override
  SearchResults build() => SearchResults.empty;

  Future<void> search(String q) async {
    final query = q.trim();
    final mySeq = ++_seq;
    if (query.isEmpty) {
      state = const AsyncData(SearchResults.empty);
      return;
    }
    state = const AsyncLoading();
    final bridge = ref.read(backendBridgeProvider);

    // Phase 1 — tracks (the primary result): show them as soon as they arrive
    // so search feels fast.
    final tracksAv =
        await AsyncValue.guard(() => bridge.searchTracks(query));
    if (mySeq != _seq) return; // a newer search superseded this one
    state = tracksAv.whenData((tracks) => SearchResults(tracks: tracks));
    if (tracksAv is! AsyncData) return;
    unawaited(ref.read(recentSearchesProvider.notifier).add(query));
    final tracks = tracksAv.value ?? const [];

    // Phase 2 — artist/album entities (slower, provider custom search): fold
    // them in when ready, only if this is still the current search.
    try {
      final (artists, albums) = await _searchEntities(bridge, query);
      if (mySeq == _seq && state.hasValue) {
        state = AsyncData(
            SearchResults(tracks: tracks, artists: artists, albums: albums));
      }
    } catch (_) {
      // Keep the track results; entity sections just stay empty.
    }
  }

  Future<(List<SearchArtist>, List<SearchAlbum>)> _searchEntities(
    BackendBridge bridge,
    String query,
  ) async {
    List<Map<String, dynamic>> providers;
    try {
      providers = await bridge.getSearchProviders();
    } catch (_) {
      providers = const [];
    }
    if (providers.isEmpty) return (const <SearchArtist>[], const <SearchAlbum>[]);

    // One unfiltered search per provider, then bucket by `item_type`. Extensions
    // disagree on the entity filter keyword ("album" vs "albums" etc.), so a
    // typed filter drops results from whichever extensions expect the other
    // spelling. Unfiltered, every extension returns all entity types each tagged
    // with `item_type` — this mirrors upstream SpotiFLAC's default (no filter →
    // bucket by item_type) and works regardless of the keyword contract.
    final entityRaw = <Map<String, dynamic>>[];
    final calls = <Future<void>>[];
    for (final p in providers) {
      final id = (p['id'] ?? '').toString();
      if (id.isEmpty) continue;
      calls.add(bridge
          .customSearch(id, query, options: {'limit': 20})
          .then((r) => entityRaw.addAll(_stampProvider(r, id)))
          .catchError((_) {}));
    }
    await Future.wait(calls);

    final artistRaw =
        entityRaw.where((m) => _itemType(m) == 'artist').toList();
    final albumRaw = entityRaw.where((m) => _itemType(m) == 'album').toList();
    return (parseArtists(artistRaw), parseAlbums(albumRaw));
  }

  /// The entity kind an unfiltered custom-search result belongs to. Extensions
  /// tag it as `item_type` ("album"/"artist"/"track"/"playlist"); fall back to
  /// `type` for the few that use that key.
  String _itemType(Map<String, dynamic> m) =>
      (m['item_type'] ?? m['type'] ?? '').toString().trim().toLowerCase();

  /// Stamps the queried [providerId] onto each entity result so the album/artist
  /// route id resolves to `provider:id`. Extensions don't reliably echo
  /// `provider_id`/`source`; without this, an un-echoed result falls back to a
  /// bare id and AlbumScreen misroutes it to Spotify's handleUrl — the album
  /// then fails to load. Mirrors upstream SpotiFLAC stamping source at search
  /// time. Only fills the field when the extension left it blank.
  List<Map<String, dynamic>> _stampProvider(
    List<Map<String, dynamic>> results,
    String providerId,
  ) {
    for (final m in results) {
      final existing = (m['provider_id'] ?? m['source'] ?? '').toString().trim();
      if (existing.isEmpty) m['provider_id'] = providerId;
    }
    return results;
  }

  Track _trackFromResolved(Map<String, dynamic> m) => Track(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        artists: (m['artists'] ?? m['artist'] ?? '').toString(),
        albumName: m['album_name']?.toString(),
        coverUrl: (m['images'] ?? m['cover_url'])?.toString(),
        durationMs: (m['duration_ms'] as num?)?.toInt(),
      );

  Future<void> resolveFromUrl(String url) async {
    state = const AsyncLoading();
    try {
      final result = await ref.read(backendBridgeProvider).handleUrl(url);
      if (result == null) {
        state = const AsyncData(SearchResults.empty);
        return;
      }
      final type = result['type']?.toString() ?? '';
      List<Track> tracks;
      if (type == 'track' && result['track'] is Map) {
        tracks = [_trackFromResolved(result['track'] as Map<String, dynamic>)];
      } else if ((type == 'album' || type == 'playlist' || type == 'artist') &&
          result['tracks'] is List) {
        tracks = (result['tracks'] as List)
            .whereType<Map<String, dynamic>>()
            .map(_trackFromResolved)
            .toList();
      } else {
        tracks = [];
      }
      state = AsyncData(SearchResults(tracks: tracks));
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final searchProvider =
    AsyncNotifierProvider<SearchNotifier, SearchResults>(SearchNotifier.new);

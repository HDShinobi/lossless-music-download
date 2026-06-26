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

    final artistRaw = <Map<String, dynamic>>[];
    final albumRaw = <Map<String, dynamic>>[];
    final calls = <Future<void>>[];

    for (final p in providers) {
      final id = (p['id'] ?? '').toString();
      if (id.isEmpty) continue;
      calls.add(bridge
          .customSearch(id, query, options: {'filter': 'artist', 'limit': 10})
          .then(artistRaw.addAll)
          .catchError((_) {}));
      calls.add(bridge
          .customSearch(id, query, options: {'filter': 'album', 'limit': 10})
          .then(albumRaw.addAll)
          .catchError((_) {}));
    }
    await Future.wait(calls);
    return (parseArtists(artistRaw), parseAlbums(albumRaw));
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

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/search_entities.dart';
import '../models/track.dart';
import '../services/backend_bridge.dart';
import 'extensions_provider.dart';
import 'recent_searches_provider.dart';

class SearchNotifier extends AsyncNotifier<SearchResults> {
  @override
  SearchResults build() => SearchResults.empty;

  Future<void> search(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      state = const AsyncData(SearchResults.empty);
      return;
    }
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() => _search(query));
    state = result;
    if (result is AsyncData) {
      unawaited(ref.read(recentSearchesProvider.notifier).add(query));
    }
  }

  /// Fetches tracks (metadata search) plus artist/album entities (provider
  /// custom search) in parallel. Tracks are the primary result; artist/album
  /// sections populate only for providers that support entity search.
  Future<SearchResults> _search(String query) async {
    final bridge = ref.read(backendBridgeProvider);
    final tracksFuture = bridge.searchTracks(query);
    final entitiesFuture = _searchEntities(bridge, query);

    final tracks = await tracksFuture;
    final (artists, albums) = await entitiesFuture;
    return SearchResults(tracks: tracks, artists: artists, albums: albums);
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

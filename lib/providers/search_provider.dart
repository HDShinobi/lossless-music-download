import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import 'extensions_provider.dart';

class SearchNotifier extends AsyncNotifier<List<Track>> {
  @override
  List<Track> build() => [];

  Future<void> search(String q) async {
    if (q.trim().isEmpty) {
      state = const AsyncData([]);
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(backendBridgeProvider).searchTracks(q.trim()),
    );
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
        state = const AsyncData([]);
        return;
      }
      final type = result['type']?.toString() ?? '';
      List<Track> tracks;
      if (type == 'track' && result['track'] is Map) {
        tracks = [_trackFromResolved(result['track'] as Map<String, dynamic>)];
      } else if ((type == 'album' || type == 'playlist') &&
          result['tracks'] is List) {
        tracks = (result['tracks'] as List)
            .whereType<Map<String, dynamic>>()
            .map(_trackFromResolved)
            .toList();
      } else {
        tracks = [];
      }
      state = AsyncData(tracks);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final searchProvider =
    AsyncNotifierProvider<SearchNotifier, List<Track>>(SearchNotifier.new);

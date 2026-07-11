import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/screens/album_screen.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';

/// Records how the album/playlist resolution called the backend.
class _RecordingBridge extends BackendBridge {
  final List<List<String>> metadataCalls = [];
  final List<String> urlCalls = [];

  @override
  Future<Map<String, dynamic>?> getProviderMetadata(
      String providerId, String resourceType, String resourceId) async {
    metadataCalls.add([providerId, resourceType, resourceId]);
    return {
      'track_list': [
        {'id': 't1', 'name': 'Track', 'artists': 'A'}
      ]
    };
  }

  @override
  Future<Map<String, dynamic>?> handleUrl(String url) async {
    urlCalls.add(url);
    return {
      'type': 'playlist',
      'tracks': [
        {'id': 't1', 'name': 'Track', 'artists': 'A'}
      ]
    };
  }
}

void main() {
  group('resolveAlbumData resource type', () {
    test('playlist provider:id resolves via getProviderMetadata "playlist"',
        () async {
      final b = _RecordingBridge();
      await resolveAlbumData(
        b,
        const AlbumRouteArgs(
            id: 'spotify-web:pl1', name: 'P', artist: '', resourceType: 'playlist'),
      );
      expect(b.metadataCalls.single, ['spotify-web', 'playlist', 'pl1']);
    });

    test('playlist bare id resolves via the /playlist/ Spotify URL', () async {
      final b = _RecordingBridge();
      final data = await resolveAlbumData(
        b,
        const AlbumRouteArgs(
            id: 'pl9', name: 'P', artist: '', resourceType: 'playlist'),
      );
      expect(b.urlCalls.single, 'https://open.spotify.com/playlist/pl9');
      expect(data.tracks, hasLength(1));
    });

    test('album is still the default resource type', () async {
      final b = _RecordingBridge();
      await resolveAlbumData(
        b,
        const AlbumRouteArgs(id: 'deezer:1', name: 'A', artist: ''),
      );
      expect(b.metadataCalls.single, ['deezer', 'album', '1']);
    });
  });
}

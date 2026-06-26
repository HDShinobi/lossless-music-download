import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/screens/album_screen.dart';

void main() {
  const args = AlbumRouteArgs(
    id: 'deezer:123',
    name: 'Fallback Album',
    artist: 'Fallback Artist',
    coverUrl: 'http://fallback/cover.jpg',
  );

  group('albumFromProviderMetadata', () {
    test('parses track_list + album_info from a provider metadata result', () {
      final result = <String, dynamic>{
        'album_info': {
          'name': 'Real Album',
          'artists': 'Real Artist',
          'cover_url': 'http://real/cover.jpg',
        },
        'track_list': [
          {'id': 't1', 'name': 'Track One', 'artists': 'Real Artist'},
          {'id': 't2', 'name': 'Track Two', 'artists': 'Real Artist'},
        ],
      };

      final data = albumFromProviderMetadata(result, args);

      expect(data.name, 'Real Album');
      expect(data.artist, 'Real Artist');
      expect(data.coverUrl, 'http://real/cover.jpg');
      expect(data.tracks, hasLength(2));
      expect(data.tracks.first.name, 'Track One');
    });

    test('falls back to route args when the result omits fields', () {
      final data = albumFromProviderMetadata(<String, dynamic>{}, args);

      expect(data.name, 'Fallback Album');
      expect(data.artist, 'Fallback Artist');
      expect(data.coverUrl, 'http://fallback/cover.jpg');
      expect(data.tracks, isEmpty);
    });

    test('accepts a top-level tracks key as an alias for track_list', () {
      final result = <String, dynamic>{
        'tracks': [
          {'id': 't1', 'name': 'Only Track', 'artists': 'A'},
        ],
      };

      final data = albumFromProviderMetadata(result, args);

      expect(data.tracks, hasLength(1));
      expect(data.tracks.single.name, 'Only Track');
    });
  });

  group('albumFromSpotifyResult', () {
    test('parses tracks when type is album', () {
      final result = <String, dynamic>{
        'type': 'album',
        'name': 'Spotify Album',
        'artist': 'Spotify Artist',
        'tracks': [
          {'id': 's1', 'name': 'S Track', 'artists': 'Spotify Artist'},
        ],
      };

      final data = albumFromSpotifyResult(result, args);

      expect(data.name, 'Spotify Album');
      expect(data.artist, 'Spotify Artist');
      expect(data.tracks, hasLength(1));
    });

    test('returns no tracks for a non-album/playlist type', () {
      final result = <String, dynamic>{
        'type': 'track',
        'tracks': [
          {'id': 's1', 'name': 'S Track', 'artists': 'X'},
        ],
      };

      final data = albumFromSpotifyResult(result, args);

      expect(data.tracks, isEmpty);
    });
  });
}

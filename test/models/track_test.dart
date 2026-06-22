import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/track.dart';

void main() {
  group('Track.fromJson (rich fields)', () {
    test('parses full metadata from the search JSON', () {
      final t = Track.fromJson(const {
        'id': 'qobuz:123',
        'name': 'Easy On Me',
        'artists': 'Adele',
        'album_name': '30',
        'album_artist': 'Adele',
        'cover_url': 'https://img/cover.jpg',
        'isrc': 'GBARL2100xxx',
        'duration_ms': 224000,
        'source': 'qobuz-web',
        'track_number': 1,
        'disc_number': 1,
        'total_tracks': 12,
        'total_discs': 1,
        'release_date': '2021-11-19',
        'composer': 'Adele Adkins',
        'audio_quality': 'Hi-Res',
        'audio_modes': 'DOLBY_ATMOS',
      });
      expect(t.id, 'qobuz:123');
      expect(t.albumArtist, 'Adele');
      expect(t.source, 'qobuz-web');
      expect(t.trackNumber, 1);
      expect(t.totalTracks, 12);
      expect(t.releaseDate, '2021-11-19');
      expect(t.composer, 'Adele Adkins');
      expect(t.qualityBadge, 'Hi-Res');
      expect(t.isAtmos, isTrue);
      expect(t.durationMs, 224000);
    });

    test('falls back across key aliases + duration-in-seconds', () {
      final t = Track.fromJson(const {
        'id': 'x',
        'name': 'S',
        'artist': 'A', // alias of artists
        'album': 'Alb', // alias of album_name
        'images': 'http://c', // alias of cover_url
        'duration': 200, // seconds -> ms
      });
      expect(t.artists, 'A');
      expect(t.albumName, 'Alb');
      expect(t.coverUrl, 'http://c');
      expect(t.durationMs, 200000);
      expect(t.qualityBadge, isNull);
      expect(t.isAtmos, isFalse);
    });
  });
}

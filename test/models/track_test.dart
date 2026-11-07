import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/track.dart';

void main() {
  group('Track.fromJson (rich fields)', () {
    test('parses snake_case and camelCase tagging fields', () {
      for (final input in [
        {'explicit': true, 'upc': '00123', 'album_type': 'album',
          'deezer_id': 42, 'playlist_position': 3,
          'disc_number': 2, 'total_discs': 3},
        {'isExplicit': 1, 'barcode': '00123', 'albumType': 'album',
          'deezerId': 42, 'playlistPosition': 3,
          'discNumber': 2, 'totalDiscs': 3},
      ]) {
        final track = Track.fromJson(input);
        expect(track.explicit, true);
        expect(track.upc, '00123');
        expect(track.albumType, 'album');
        expect(track.deezerId, '42');
        expect(track.playlistPosition, 3);
        expect(track.discNumber, 2);
        expect(track.totalDiscs, 3);
      }
    });

    test('parses upstream explicit flag representations without inventing data', () {
      for (final value in [true, 1, '1', ' TRUE ']) {
        expect(Track.fromJson({'explicit': value}).explicit, true);
      }
      for (final value in [false, 0, '0', 'false']) {
        expect(Track.fromJson({'is_explicit': value}).explicit, false);
      }
      for (final value in [null, '', 'null', [], {}]) {
        expect(Track.fromJson({'explicit': value}).explicit, isNull);
      }
    });

    test('normalizes blank metadata and rejects unknown playlist positions', () {
      for (final value in [null, '', '  ', 'null']) {
        final track = Track.fromJson({
          'upc': value, 'album_type': value, 'deezer_id': value,
        });
        expect(track.upc, isNull);
        expect(track.albumType, isNull);
        expect(track.deezerId, isNull);
      }
      for (final value in [null, 0, -1, 'unknown']) {
        expect(Track.fromJson({'playlistPosition': value}).playlistPosition,
          isNull);
      }
    });

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

  group('Track preview', () {
    test('parses preview_url and reports hasPreview', () {
      final t = Track.fromJson(const {
        'id': 'x',
        'name': 'S',
        'artists': 'A',
        'preview_url': 'https://cdn/preview.mp3',
      });
      expect(t.previewUrl, 'https://cdn/preview.mp3');
      expect(t.hasPreview, isTrue);
    });

    test('accepts previewUrl camelCase alias', () {
      final t = Track.fromJson(const {
        'id': 'x',
        'name': 'S',
        'artists': 'A',
        'previewUrl': 'https://cdn/p.mp3',
      });
      expect(t.previewUrl, 'https://cdn/p.mp3');
      expect(t.hasPreview, isTrue);
    });

    test('hasPreview is false when preview_url absent or empty', () {
      final none = Track.fromJson(const {'id': 'x', 'name': 'S', 'artists': 'A'});
      final empty = Track.fromJson(
        const {'id': 'x', 'name': 'S', 'artists': 'A', 'preview_url': ''},
      );
      expect(none.previewUrl, isNull);
      expect(none.hasPreview, isFalse);
      expect(empty.hasPreview, isFalse);
    });
  });
}

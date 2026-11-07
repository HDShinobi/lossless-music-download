import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/download_request.dart';
import 'package:lossless_music_download/models/metadata_separators.dart';

void main() {
  group('DownloadRequest.toJson', () {
    test('serializes custom tag mode and all four separators', () {
      final json = const DownloadRequest(trackName: 'S', artistName: 'A',
        outputDir: '/dl', filenameFormat: '{title}', artistTagMode: 'split_vorbis',
        metadataSeparators: MetadataSeparators(artist: '; ', albumArtist: ' / ',
          composer: ', ', genre: ' | ')).toJson();
      expect(json['filename_format'], '{title}');
      expect(json['artist_tag_mode'], 'split_vorbis');
      expect(json['metadata_separators'], {'artist': '; ', 'album_artist': ' / ',
        'composer': ', ', 'genre': ' | '});
    });

    test('default formatting payload preserves existing behavior', () {
      final json = const DownloadRequest(trackName: 'S', artistName: 'A',
        outputDir: '/dl').toJson();
      expect(json['artist_tag_mode'], 'joined');
      expect(json['filename_format'], '{artist} - {title}');
      expect(json.containsKey('metadata_separators'), isFalse);
      expect(json.containsKey('album_folder_template'), isFalse);
    });

    test('emits only available tagging fields and meaningful playlist position', () {
      final json = const DownloadRequest(
        trackName: 'Song', artistName: 'Artist', outputDir: '/dl',
        explicit: true, upc: '00123', albumType: 'compilation',
        deezerId: '42', playlistPosition: 3,
      ).toJson();
      expect(json['explicit'], true);
      expect(json['upc'], '00123');
      expect(json['album_type'], 'compilation');
      expect(json['deezer_id'], '42');
      expect(json['playlist_position'], 3);
    });

    test('omits empty tagging strings and nonpositive playlist positions', () {
      for (final position in [null, 0, -1]) {
        final json = DownloadRequest(
          trackName: 'Song', artistName: 'Artist', outputDir: '/dl',
          explicit: false, upc: '', albumType: '  ', deezerId: '',
          playlistPosition: position,
        ).toJson();
        expect(json['explicit'], false);
        for (final key in ['upc', 'album_type', 'deezer_id', 'playlist_position']) {
          expect(json.containsKey(key), false, reason: key);
        }
      }
    });

    test('uses upstream default cover size and omits unavailable metadata', () {
      final json = const DownloadRequest(
        trackName: 'Song', artistName: 'Artist', outputDir: '/dl',
      ).toJson();
      expect(json['cover_max_dimension'], 0);
      for (final key in ['explicit', 'upc', 'album_type', 'deezer_id',
        'playlist_position']) {
        expect(json.containsKey(key), false, reason: key);
      }
    });

    test('includes item_id when itemId is set', () {
      const req = DownloadRequest(
        trackName: 'My Song',
        artistName: 'Artist',
        outputDir: '/downloads',
        itemId: 'dl_123_tid1',
      );
      expect(req.toJson()['item_id'], 'dl_123_tid1');
    });

    test('omits item_id when itemId is null', () {
      const req = DownloadRequest(
        trackName: 'My Song',
        artistName: 'Artist',
        outputDir: '/downloads',
      );
      expect(req.toJson().containsKey('item_id'), isFalse);
    });

    test('emits use_fallback true by default', () {
      const req = DownloadRequest(
        trackName: 'My Song',
        artistName: 'Artist',
        outputDir: '/downloads',
      );
      expect(req.toJson()['use_fallback'], isTrue);
    });

    test('emits use_fallback false when fallback is disabled', () {
      const req = DownloadRequest(
        trackName: 'My Song',
        artistName: 'Artist',
        outputDir: '/downloads',
        useFallback: false,
      );
      expect(req.toJson()['use_fallback'], isFalse);
    });

    test('includes service when set, omits it when null', () {
      const withService = DownloadRequest(
        trackName: 'My Song',
        artistName: 'Artist',
        outputDir: '/downloads',
        service: 'qobuz-web',
      );
      expect(withService.toJson()['service'], 'qobuz-web');

      const withoutService = DownloadRequest(
        trackName: 'My Song',
        artistName: 'Artist',
        outputDir: '/downloads',
      );
      expect(withoutService.toJson().containsKey('service'), isFalse);
    });

    // --- P1 new fields ---

    test('always emits contract_version 1', () {
      const req = DownloadRequest(
        trackName: 'X', artistName: 'Y', outputDir: '/dl',
      );
      expect(req.toJson()['contract_version'], 1);
    });

    test('emits artist_tag_mode joined by default', () {
      const req = DownloadRequest(
        trackName: 'X', artistName: 'Y', outputDir: '/dl',
      );
      expect(req.toJson()['artist_tag_mode'], 'joined');
    });

    test('emits lyrics_mode embed by default', () {
      const req = DownloadRequest(
        trackName: 'X', artistName: 'Y', outputDir: '/dl',
      );
      expect(req.toJson()['lyrics_mode'], 'embed');
    });

    test('emits songlink_region US by default', () {
      const req = DownloadRequest(
        trackName: 'X', artistName: 'Y', outputDir: '/dl',
      );
      expect(req.toJson()['songlink_region'], 'US');
    });

    test('emits genre label copyright when set', () {
      const req = DownloadRequest(
        trackName: 'X',
        artistName: 'Y',
        outputDir: '/dl',
        genre: 'Jazz',
        label: 'Blue Note',
        copyright: '© 1959 Blue Note',
      );
      final j = req.toJson();
      expect(j['genre'], 'Jazz');
      expect(j['label'], 'Blue Note');
      expect(j['copyright'], '© 1959 Blue Note');
    });

    test('omits genre label copyright when null', () {
      const req = DownloadRequest(
        trackName: 'X', artistName: 'Y', outputDir: '/dl',
      );
      final j = req.toJson();
      expect(j.containsKey('genre'), isFalse);
      expect(j.containsKey('label'), isFalse);
      expect(j.containsKey('copyright'), isFalse);
    });

    test('writeLrcSidecar serializes to write_lrc_sidecar', () {
      final json = const DownloadRequest(
        trackName: 't', artistName: 'a', outputDir: '/d',
        writeLrcSidecar: true,
      ).toJson();
      expect(json['write_lrc_sidecar'], isTrue);
    });

    test('write_lrc_sidecar defaults false', () {
      final json = const DownloadRequest(
        trackName: 't', artistName: 'a', outputDir: '/d').toJson();
      expect(json['write_lrc_sidecar'], isFalse);
    });
  });
}

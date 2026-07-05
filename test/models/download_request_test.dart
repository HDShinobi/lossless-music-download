import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/download_request.dart';

void main() {
  group('DownloadRequest.toJson', () {
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

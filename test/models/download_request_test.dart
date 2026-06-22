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
      final json = req.toJson();
      expect(json['item_id'], 'dl_123_tid1');
    });

    test('omits item_id when itemId is null', () {
      const req = DownloadRequest(
        trackName: 'My Song',
        artistName: 'Artist',
        outputDir: '/downloads',
      );
      final json = req.toJson();
      expect(json.containsKey('item_id'), isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/models/download_request.dart';

void main() {
  test('Track.fromJson maps core fields', () {
    final t = Track.fromJson({
      'id': 'x1', 'name': 'Song', 'artists': 'Artist',
      'album_name': 'Album', 'cover_url': 'http://c', 'isrc': 'ISRC1', 'duration_ms': 200000,
    });
    expect(t.id, 'x1');
    expect(t.name, 'Song');
    expect(t.isrc, 'ISRC1');
  });
  test('DownloadRequest.toJson includes required fields', () {
    final r = DownloadRequest(title: 'Song', artist: 'Artist', isrc: 'ISRC1', outputDir: '/d');
    final j = r.toJson();
    expect(j['title'], 'Song');
    expect(j['useExtensions'], true);
    expect(j['outputDir'], '/d');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/models/download_request.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/models/download_progress.dart';

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

  test('DownloadRequest.toJson emits Go snake_case keys', () {
    final r = DownloadRequest(
      trackName: 'Song', artistName: 'Artist', isrc: 'ISRC1',
      outputDir: '/d', spotifyId: 'spid1', albumName: 'Album',
    );
    final j = r.toJson();
    // Required snake_case keys must be present
    expect(j['track_name'], 'Song');
    expect(j['artist_name'], 'Artist');
    expect(j['output_dir'], '/d');
    expect(j['spotify_id'], 'spid1');
    expect(j['album_name'], 'Album');
    expect(j['filename_format'], isNotNull);
    expect(j['use_extensions'], true);
    expect(j['embed_metadata'], true);
    expect(j['embed_max_quality_cover'], true);
    expect(j['embed_lyrics'], true);
    // Stale camelCase keys must NOT be present
    expect(j.containsKey('title'), isFalse);
    expect(j.containsKey('artist'), isFalse);
    expect(j.containsKey('outputDir'), isFalse);
    expect(j.containsKey('spotifyId'), isFalse);
    expect(j.containsKey('albumName'), isFalse);
    expect(j.containsKey('filenameFormat'), isFalse);
    expect(j.containsKey('useExtensions'), isFalse);
    expect(j.containsKey('embedMetadata'), isFalse);
    expect(j.containsKey('embedCover'), isFalse);
    expect(j.containsKey('embedLyrics'), isFalse);
    expect(j.containsKey('audioFormat'), isFalse);
  });

  test('InstalledExtension.fromJson parses Go-shaped JSON (display_name + types)', () {
    final ext = InstalledExtension.fromJson({
      'id': 'deezer',
      'name': 'deezer',
      'display_name': 'Deezer',
      'version': '1.1.5',
      'enabled': true,
      'types': ['download_provider', 'metadata_provider'],
    });
    expect(ext.id, 'deezer');
    expect(ext.name, 'Deezer'); // reads display_name
    expect(ext.version, '1.1.5');
    expect(ext.enabled, isTrue);
    expect(ext.types, containsAll(['download_provider', 'metadata_provider']));
    expect(ext.types.length, 2);
  });

  test('InstalledExtension.fromJson parses full Go-shaped JSON with permissions + provider flags', () {
    final ext = InstalledExtension.fromJson({
      'id': 'tidal',
      'name': 'tidal',
      'display_name': 'Tidal HiFi',
      'version': '2.0.0',
      'description': 'Tidal lossless download extension',
      'icon_path': '/data/ext/tidal/icon.png',
      'types': ['download_provider', 'lyrics_provider'],
      'enabled': true,
      'status': 'active',
      'error_message': '',
      'permissions': ['network', 'storage', 'credentials'],
      'has_metadata_provider': false,
      'has_download_provider': true,
      'has_lyrics_provider': true,
    });

    expect(ext.id, 'tidal');
    expect(ext.displayName, 'Tidal HiFi');
    expect(ext.name, 'Tidal HiFi'); // name mirrors displayName (reads display_name)
    expect(ext.description, 'Tidal lossless download extension');
    expect(ext.iconPath, '/data/ext/tidal/icon.png');
    expect(ext.status, 'active');
    expect(ext.types, containsAll(['download_provider', 'lyrics_provider']));
    expect(ext.permissions, containsAll(['network', 'storage', 'credentials']));
    expect(ext.permissions.length, 3);
    expect(ext.hasMetadataProvider, isFalse);
    expect(ext.hasDownloadProvider, isTrue);
    expect(ext.hasLyricsProvider, isTrue);
  });

  test('InstalledExtension.fromJson tolerates missing optional fields', () {
    final ext = InstalledExtension.fromJson({'id': 'minimal', 'name': 'min', 'version': '0.1'});
    expect(ext.permissions, isEmpty);
    expect(ext.hasMetadataProvider, isFalse);
    expect(ext.hasDownloadProvider, isFalse);
    expect(ext.hasLyricsProvider, isFalse);
    expect(ext.iconPath, isNull);
    expect(ext.status, '');
    expect(ext.description, '');
  });

  test('DownloadProgress.fromJson round-trip', () {
    final p = DownloadProgress.fromJson({
      'item_id': 'abc',
      'status': 'downloading',
      'progress': 0.42,
      'bytes_received': 1024,
    });
    expect(p.itemId, 'abc');
    expect(p.status, 'downloading');
    expect(p.progress, closeTo(0.42, 0.001));
    expect(p.bytesReceived, 1024);
  });
}

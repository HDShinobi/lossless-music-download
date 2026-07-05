import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/installed_extension.dart';

void main() {
  test('hasHomeFeed true when capabilities.homeFeed == true', () {
    final e = InstalledExtension.fromJson({
      'id': 'ytmusic', 'name': 'yt', 'version': '1', 'enabled': true,
      'types': const [], 'display_name': 'YT', 'description': '', 'status': '',
      'permissions': const [], 'capabilities': {'homeFeed': true},
    });
    expect(e.hasHomeFeed, isTrue);
  });

  test('hasHomeFeed false when capabilities absent', () {
    final e = InstalledExtension.fromJson({
      'id': 'x', 'name': 'x', 'version': '1', 'enabled': true,
      'types': const [], 'display_name': 'X', 'description': '', 'status': '',
      'permissions': const [],
    });
    expect(e.hasHomeFeed, isFalse);
    expect(e.capabilities, isEmpty);
  });

  test('const constructor works without capabilities (backward compat)', () {
    const e = InstalledExtension(
      id: 'x', name: 'x', version: '1', enabled: true, types: [],
      displayName: 'X', description: '', status: '', permissions: [],
      hasMetadataProvider: false, hasDownloadProvider: false, hasLyricsProvider: false,
    );
    expect(e.hasHomeFeed, isFalse);
  });
}

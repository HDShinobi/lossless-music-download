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

  test('parses quality_options into qualityOptions', () {
    final e = InstalledExtension.fromJson({
      'id': 'tidal', 'name': 'tidal', 'version': '1', 'enabled': true,
      'types': const [], 'display_name': 'Tidal', 'description': '', 'status': '',
      'permissions': const [],
      'quality_options': [
        {'id': 'HI_RES_LOSSLESS', 'label': 'Hi-Res FLAC', 'description': 'Up to 24-bit / 192 kHz'},
        {'id': 'LOSSLESS', 'label': 'FLAC Lossless', 'description': '16-bit / 44.1 kHz'},
      ],
    });
    expect(e.qualityOptions, hasLength(2));
    expect(e.qualityOptions.first.id, 'HI_RES_LOSSLESS');
    expect(e.qualityOptions.first.label, 'Hi-Res FLAC');
    expect(e.qualityOptions.first.description, 'Up to 24-bit / 192 kHz');
  });

  test('qualityOptions empty when quality_options absent', () {
    final e = InstalledExtension.fromJson({
      'id': 'x', 'name': 'x', 'version': '1', 'enabled': true,
      'types': const [], 'display_name': 'X', 'description': '', 'status': '',
      'permissions': const [],
    });
    expect(e.qualityOptions, isEmpty);
  });

  test('quality option label falls back to id when label missing', () {
    final e = InstalledExtension.fromJson({
      'id': 'x', 'name': 'x', 'version': '1', 'enabled': true,
      'types': const [], 'display_name': 'X', 'description': '', 'status': '',
      'permissions': const [],
      'quality_options': [
        {'id': 'LOSSLESS'},
      ],
    });
    expect(e.qualityOptions.single.label, 'LOSSLESS');
    expect(e.qualityOptions.single.description, '');
  });
}

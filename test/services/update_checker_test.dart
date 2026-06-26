import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/services/update_checker.dart';

void main() {
  group('isNewerVersion', () {
    test('a higher patch/minor/major is newer', () {
      expect(isNewerVersion('0.2.0', '0.1.0'), isTrue);
      expect(isNewerVersion('0.2.1', '0.2.0'), isTrue);
      expect(isNewerVersion('1.0.0', '0.9.9'), isTrue);
    });

    test('equal or older is not newer', () {
      expect(isNewerVersion('0.2.0', '0.2.0'), isFalse);
      expect(isNewerVersion('0.1.9', '0.2.0'), isFalse);
      expect(isNewerVersion('0.9.9', '1.0.0'), isFalse);
    });

    test('build suffixes and prerelease tags are ignored for the comparison',
        () {
      expect(isNewerVersion('0.2.0-rc1', '0.1.0'), isTrue);
      expect(isNewerVersion('0.2.0+5', '0.2.0+2'), isFalse);
    });

    test('missing patch component is treated as 0', () {
      expect(isNewerVersion('0.3', '0.2.9'), isTrue);
      expect(isNewerVersion('1', '0.9.9'), isTrue);
    });
  });

  group('parseLatestRelease', () {
    Map<String, dynamic> release({
      String tag = 'v0.2.0',
      String body = 'Changelog here',
      bool prerelease = false,
      List<Map<String, dynamic>>? assets,
    }) =>
        {
          'tag_name': tag,
          'body': body,
          'prerelease': prerelease,
          'html_url':
              'https://github.com/HDShinobi/lossless-music-releases/releases/tag/$tag',
          'assets': assets ??
              [
                {
                  'name': 'lossless-music-v0.2.0.apk',
                  'browser_download_url':
                      'https://github.com/HDShinobi/lossless-music-releases/releases/download/v0.2.0/lossless-music-v0.2.0.apk',
                },
              ],
        };

    test('extracts version (v-stripped), changelog, apk url, prerelease', () {
      final info = parseLatestRelease(release())!;
      expect(info.version, '0.2.0');
      expect(info.changelog, 'Changelog here');
      expect(info.apkUrl, endsWith('lossless-music-v0.2.0.apk'));
      expect(info.isPrerelease, isFalse);
    });

    test('picks the .apk asset, ignoring non-apk assets', () {
      final info = parseLatestRelease(release(assets: [
        {'name': 'notes.txt', 'browser_download_url': 'http://x/notes.txt'},
        {
          'name': 'lossless-music-v0.2.0.apk',
          'browser_download_url': 'http://x/app.apk',
        },
      ]))!;
      expect(info.apkUrl, 'http://x/app.apk');
    });

    test('returns null when the tag is empty', () {
      expect(parseLatestRelease(release(tag: '')), isNull);
    });

    test('apkUrl is empty when no apk asset is present', () {
      final info = parseLatestRelease(release(assets: []))!;
      expect(info.apkUrl, isEmpty);
    });
  });
}

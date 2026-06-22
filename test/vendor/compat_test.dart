import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/vendor/spotiflac/compat_l10n.dart';
import 'package:lossless_music_download/vendor/spotiflac/compat_platform_bridge.dart';

void main() {
  group('AnalysisL10n (compat l10n shim)', () {
    test('resolves key strings non-empty for vi and en', () {
      for (final lang in const ['vi', 'en']) {
        final l = AnalysisL10n(lang);
        expect(l.audioAnalysisTitle, isNotEmpty, reason: lang);
        expect(l.audioAnalysisSpectralCutoff, isNotEmpty, reason: lang);
        expect(l.audioAnalysisNyquist, isNotEmpty, reason: lang);
      }
    });
  });

  group('PlatformBridge (compat stub)', () {
    test('safStat returns the file size for a direct path', () async {
      final f = File('${Directory.systemTemp.path}/compat_safstat_test.bin')
        ..writeAsBytesSync(List<int>.filled(1234, 0));
      addTearDown(() {
        if (f.existsSync()) f.deleteSync();
      });

      final stat = await PlatformBridge.safStat(f.path);
      expect(stat['size'], 1234);
    });

    test('copyContentUriToTemp returns null for direct paths', () async {
      expect(await PlatformBridge.copyContentUriToTemp('/music/x.flac'), isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/util/format_progress.dart';

void main() {
  group('formatProgressLine', () {
    // Exact example from spec:
    // formatProgressLine(doneBytes: 196083712, totalBytes: 327155712,
    //   speedBytesPerSec: 11953766, eta: Duration(seconds: 11))
    // → '187.0 MB / 312.0 MB · 60% · 11.4 MB/s · ~0m 11s'
    test('full inputs produce exact spec string', () {
      final result = formatProgressLine(
        doneBytes: 196083712,
        totalBytes: 327155712,
        speedBytesPerSec: 11953766,
        eta: const Duration(seconds: 11),
      );
      expect(result, '187.0 MB / 312.0 MB · 60% · 11.4 MB/s · ~0m 11s');
    });

    test('only doneBytes shows single MB segment', () {
      final result = formatProgressLine(doneBytes: 196083712);
      expect(result, '187.0 MB');
    });

    test('doneBytes + totalBytes (no speed/eta) shows done/total and pct', () {
      final result = formatProgressLine(
        doneBytes: 196083712,
        totalBytes: 327155712,
      );
      expect(result, '187.0 MB / 312.0 MB · 60%');
    });

    test('totalBytes == 0 with no bytes/progress falls back to 0%', () {
      final result = formatProgressLine(doneBytes: 0, totalBytes: 0);
      expect(result, '0%');
    });

    test('totalBytes == 0 with progress shows percentage (extension flow)', () {
      final result = formatProgressLine(
        doneBytes: 0,
        totalBytes: 0,
        progress: 0.45,
      );
      expect(result, '45%');
    });

    test('doneBytes > 0 with totalBytes == 0 shows only done MB segment', () {
      final result = formatProgressLine(doneBytes: 5242880, totalBytes: 0);
      expect(result, '5.0 MB');
    });
  });
}

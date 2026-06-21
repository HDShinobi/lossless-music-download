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
  });
}

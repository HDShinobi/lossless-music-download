import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/audio_quality.dart';

void main() {
  group('AudioQuality', () {
    test('parses backend JSON and formats labels', () {
      final q = AudioQuality.fromJson(const {
        'bit_depth': 24,
        'sample_rate': 96000,
        'bitrate': 2304,
        'duration': 245,
        'codec': 'flac',
      });
      expect(q.bitDepth, 24);
      expect(q.sampleRate, 96000);
      expect(q.bitrate, 2304);
      expect(q.codec, 'flac');
      expect(q.hasData, isTrue);
      expect(q.bitDepthLabel, '24-bit');
      expect(q.sampleRateLabel, '96.0 kHz');
    });

    test('handles missing/lossy fields gracefully', () {
      final q = AudioQuality.fromJson(const {'sample_rate': 44100});
      expect(q.bitDepth, 0);
      expect(q.bitDepthLabel, ''); // unknown bit depth -> no label
      expect(q.sampleRateLabel, '44.1 kHz');
      expect(q.hasData, isTrue);

      final empty = AudioQuality.fromJson(const {});
      expect(empty.hasData, isFalse);
    });
  });
}

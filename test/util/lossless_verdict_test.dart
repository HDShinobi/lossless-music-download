import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/util/lossless_verdict.dart';

void main() {
  group('assessLossless', () {
    test('lossy codec is reported as lossy regardless of cutoff', () {
      expect(
        assessLossless(codec: 'mp3', sampleRate: 44100, cutoffHz: 20000),
        LosslessVerdict.lossy,
      );
      expect(
        assessLossless(codec: 'aac', sampleRate: 44100, cutoffHz: 19000),
        LosslessVerdict.lossy,
      );
      expect(
        assessLossless(codec: 'opus', sampleRate: 48000, cutoffHz: 20000),
        LosslessVerdict.lossy,
      );
    });

    test('lossless codec with full-band cutoff is lossless', () {
      expect(
        assessLossless(codec: 'flac', sampleRate: 44100, cutoffHz: 21000),
        LosslessVerdict.lossless,
      );
      // Hi-res genuine: 96k file with ~20kHz musical content is still lossless
      // (music rarely carries ultrasonic energy).
      expect(
        assessLossless(codec: 'flac', sampleRate: 96000, cutoffHz: 20000),
        LosslessVerdict.lossless,
      );
    });

    test('lossless container with a low cutoff on >=44.1kHz is suspect', () {
      // FLAC that is really a transcoded MP3 — cutoff well below Nyquist.
      expect(
        assessLossless(codec: 'flac', sampleRate: 44100, cutoffHz: 16000),
        LosslessVerdict.suspectLossy,
      );
      expect(
        assessLossless(codec: 'alac', sampleRate: 48000, cutoffHz: 15500),
        LosslessVerdict.suspectLossy,
      );
    });

    test('exactly at the 18kHz threshold is NOT flagged (conservative)', () {
      expect(
        assessLossless(codec: 'flac', sampleRate: 44100, cutoffHz: 18000),
        LosslessVerdict.lossless,
      );
    });

    test('unknown cutoff or sample rate is inconclusive', () {
      expect(
        assessLossless(codec: 'flac', sampleRate: 44100, cutoffHz: null),
        LosslessVerdict.inconclusive,
      );
      expect(
        assessLossless(codec: 'flac', sampleRate: 0, cutoffHz: 20000),
        LosslessVerdict.inconclusive,
      );
    });

    test('codec match is case-insensitive', () {
      expect(
        assessLossless(codec: 'MP3', sampleRate: 44100, cutoffHz: 20000),
        LosslessVerdict.lossy,
      );
    });
  });
}

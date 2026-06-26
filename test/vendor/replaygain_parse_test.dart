import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/vendor/spotiflac/replaygain_service.dart';

void main() {
  group('parseReplayGainOutput', () {
    test('computes gain (-18 LUFS ref) and linear peak from ebur128 output', () {
      const output = '''
[Parsed_ebur128_0 @ 0x0] Summary:
  Integrated loudness:
    I:          -8.2 LUFS
    Threshold:  -18.5 LUFS
  True peak:
    Peak:       -0.2 dBFS
''';
      final rg = parseReplayGainOutput(output)!;
      // gain = -18 - (-8.2) = -9.8
      expect(rg.trackGain, '-9.80 dB');
      // peak = 10^(-0.2/20) ≈ 0.977237
      expect(double.parse(rg.trackPeak), closeTo(0.977237, 0.0001));
    });

    test('positive gain is prefixed with +', () {
      const output = 'I:         -25.0 LUFS\nPeak:       -6.0 dBFS\n';
      final rg = parseReplayGainOutput(output)!;
      // gain = -18 - (-25) = +7
      expect(rg.trackGain, '+7.00 dB');
    });

    test('uses the maximum (loudest) true peak across channels', () {
      const output =
          'I: -10.0 LUFS\nPeak: -3.0 dBFS\nPeak: -1.0 dBFS\nPeak: -5.0 dBFS\n';
      final rg = parseReplayGainOutput(output)!;
      // loudest peak = -1.0 dBFS → 10^(-1/20) ≈ 0.891251
      expect(double.parse(rg.trackPeak), closeTo(0.891251, 0.0001));
    });

    test('takes the last (summary) integrated-loudness match', () {
      const output = 'I: -30.0 LUFS\nI: -12.0 LUFS\nPeak: 0.0 dBFS\n';
      final rg = parseReplayGainOutput(output)!;
      // gain from -12 (the summary) = -18 - (-12) = -6
      expect(rg.trackGain, '-6.00 dB');
    });

    test('falls back to peak 1.0 when no true peak is present', () {
      const output = 'I: -18.0 LUFS\n';
      final rg = parseReplayGainOutput(output)!;
      expect(rg.trackGain, '+0.00 dB');
      expect(double.parse(rg.trackPeak), closeTo(1.0, 0.0001));
    });

    test('returns null when integrated loudness cannot be parsed', () {
      expect(parseReplayGainOutput('no useful data here'), isNull);
    });
  });
}

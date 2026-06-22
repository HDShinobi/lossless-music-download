/// Measured audio quality of a local file, probed by the backend
/// (`GetAudioQuality`). Mirrors the backend `AudioQuality` JSON.
class AudioQuality {
  final int bitDepth;
  final int sampleRate; // Hz
  final int bitrate; // kbps (0 if unknown)
  final int durationSec;
  final String codec;

  const AudioQuality({
    required this.bitDepth,
    required this.sampleRate,
    this.bitrate = 0,
    this.durationSec = 0,
    this.codec = '',
  });

  factory AudioQuality.fromJson(Map<String, dynamic> j) => AudioQuality(
        bitDepth: (j['bit_depth'] as num?)?.toInt() ?? 0,
        sampleRate: (j['sample_rate'] as num?)?.toInt() ?? 0,
        bitrate: (j['bitrate'] as num?)?.toInt() ?? 0,
        durationSec: (j['duration'] as num?)?.toInt() ?? 0,
        codec: (j['codec'] ?? '').toString(),
      );

  /// True when the probe yielded usable PCM parameters.
  bool get hasData => sampleRate > 0;

  /// e.g. "24-bit" (empty when bit depth is unknown, common for lossy).
  String get bitDepthLabel => bitDepth > 0 ? '$bitDepth-bit' : '';

  /// e.g. "96.0 kHz".
  String get sampleRateLabel =>
      sampleRate > 0 ? '${(sampleRate / 1000).toStringAsFixed(1)} kHz' : '';
}

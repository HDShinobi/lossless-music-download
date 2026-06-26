/// Outcome of the conservative lossless authenticity heuristic.
enum LosslessVerdict {
  /// Lossless container with full-band content — looks genuine.
  lossless,

  /// Lossless container, but the spectral cutoff is suspiciously low for the
  /// sample rate — likely a lossy source transcoded into a lossless wrapper.
  suspectLossy,

  /// The file is encoded with a lossy codec (matter-of-fact, not a warning).
  lossy,

  /// Not enough information to judge (no cutoff measured, unknown sample rate).
  inconclusive,
}

/// Lossy codecs — a file in one of these is lossy by definition.
const _lossyCodecs = {'mp3', 'aac', 'opus', 'vorbis', 'wma', 'ac3', 'eac3'};

/// Cutoff below this (Hz), on a file sampled at >= 44.1 kHz, is treated as a
/// sign of a lossy source. Deliberately conservative: genuine band-limited
/// masters (acoustic, classical) usually still reach ~18 kHz, and real MP3/AAC
/// transcodes typically cut noticeably lower.
const _suspectCutoffHz = 18000.0;

/// Assesses whether a track is genuinely lossless, using the codec plus the
/// measured spectral [cutoffHz]. Pure and side-effect free.
///
/// This is a heuristic for visual guidance, not a definitive verdict — it errs
/// toward NOT flagging (conservative) to avoid mislabelling legitimate audio.
LosslessVerdict assessLossless({
  required String codec,
  required int sampleRate,
  required double? cutoffHz,
}) {
  final c = codec.toLowerCase();
  if (_lossyCodecs.any(c.contains)) return LosslessVerdict.lossy;

  if (cutoffHz == null || sampleRate <= 0) return LosslessVerdict.inconclusive;

  if (sampleRate >= 44100 && cutoffHz < _suspectCutoffHz) {
    return LosslessVerdict.suspectLossy;
  }
  return LosslessVerdict.lossless;
}

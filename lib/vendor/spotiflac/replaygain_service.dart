// Adapted from SpotiFLAC-Mobile (MIT): lib/services/replaygain_service.dart +
// the scanReplayGain() routine from lib/services/ffmpeg_service.dart. See
// SYNC.md. The EBU R128 scan + ReplayGain math are ported verbatim; the file
// I/O is adapted to our bridge (EditFileMetadata) and ffmpeg_kit_full.
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';

import '../../services/backend_bridge.dart';

/// Result of a ReplayGain scan: tag-ready strings.
class ReplayGainResult {
  const ReplayGainResult({required this.trackGain, required this.trackPeak});

  /// e.g. "-9.80 dB" / "+7.00 dB".
  final String trackGain;

  /// Linear peak (0..1+), 6 decimals, e.g. "0.977237".
  final String trackPeak;
}

/// ReplayGain reference level (EBU R128 / ReplayGain 2.0).
const _referenceLufs = -18.0;

/// Parses FFmpeg `ebur128=peak=true` summary output into a [ReplayGainResult].
/// Pure (no FFmpeg) — unit tested. Returns null if integrated loudness is
/// absent. `gain = -18 - integratedLUFS`; `peak = 10^(maxTruePeakDbfs/20)`.
ReplayGainResult? parseReplayGainOutput(String output) {
  final integratedMatches =
      RegExp(r'I:\s+(-?\d+\.?\d*)\s+LUFS').allMatches(output);
  if (integratedMatches.isEmpty) return null;
  final integratedLufs =
      double.tryParse(integratedMatches.last.group(1) ?? '');
  if (integratedLufs == null) return null;

  double? maxPeakDbfs;
  for (final m in RegExp(r'Peak:\s+(-?\d+\.?\d*)\s+dBFS').allMatches(output)) {
    final v = double.tryParse(m.group(1) ?? '');
    if (v != null && (maxPeakDbfs == null || v > maxPeakDbfs)) {
      maxPeakDbfs = v;
    }
  }

  final gainDb = _referenceLufs - integratedLufs;
  final peakLinear =
      maxPeakDbfs != null ? math.pow(10, maxPeakDbfs / 20.0).toDouble() : 1.0;

  return ReplayGainResult(
    trackGain: '${gainDb >= 0 ? "+" : ""}${gainDb.toStringAsFixed(2)} dB',
    trackPeak: peakLinear.toStringAsFixed(6),
  );
}

/// Scans an audio file for EBU R128 loudness and writes track ReplayGain tags
/// in place. Modeled on SpotiFLAC's ReplayGainService.applyToFile.
class ReplayGainService {
  ReplayGainService._();

  /// Overridable in tests; defaults to running FFmpeg ebur128 and returning its
  /// (stderr-inclusive) output.
  static Future<String> Function(String filePath) scanRunner = _defaultScan;

  static Future<String> _defaultScan(String filePath) async {
    final session = await FFmpegKit.executeWithArguments([
      '-hide_banner',
      '-nostats',
      '-i',
      filePath,
      '-filter_complex',
      'ebur128=peak=true:framelog=quiet',
      '-f',
      'null',
      '-',
    ]);
    // ebur128 writes its summary to logs (stderr), captured here.
    final logs = await session.getAllLogsAsString();
    return logs ?? '';
  }

  /// Scans [filePath] and writes `replaygain_track_gain`/`_peak` via the backend
  /// bridge (native tag write — FLAC/M4A/WAV/AIFF/APE). Returns true on success.
  static Future<bool> applyToFile(String filePath, BackendBridge bridge) async {
    if (filePath.isEmpty) return false;
    final output = await scanRunner(filePath);
    final rg = parseReplayGainOutput(output);
    if (rg == null) return false;

    final result = await bridge.editFileMetadata(filePath, {
      'replaygain_track_gain': rg.trackGain,
      'replaygain_track_peak': rg.trackPeak,
    });
    return result['error'] == null;
  }
}

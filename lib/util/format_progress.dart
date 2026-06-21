/// Pure formatter for download progress display lines.
///
/// Builds segments joined by ' · ', including a segment ONLY when its data is
/// present. Examples:
///   formatProgressLine(doneBytes: 196083712, totalBytes: 327155712,
///     speedBytesPerSec: 11953766, eta: Duration(seconds: 11))
///   → '187.0 MB / 312.0 MB · 60% · 11.4 MB/s · ~0m 11s'
String formatProgressLine({
  required int doneBytes,
  int? totalBytes,
  double? speedBytesPerSec,
  Duration? eta,
}) {
  const mb = 1024.0 * 1024.0;
  final doneMb = doneBytes / mb;

  final segments = <String>[];

  // First segment: done MB (and total MB if available and non-zero)
  if (totalBytes != null && totalBytes > 0) {
    final totalMb = totalBytes / mb;
    segments.add('${doneMb.toStringAsFixed(1)} MB / ${totalMb.toStringAsFixed(1)} MB');
    final pct = ((doneBytes / totalBytes) * 100).round();
    segments.add('$pct%');
  } else {
    segments.add('${doneMb.toStringAsFixed(1)} MB');
  }

  // Speed segment
  if (speedBytesPerSec != null) {
    final speedMb = speedBytesPerSec / mb;
    segments.add('${speedMb.toStringAsFixed(1)} MB/s');
  }

  // ETA segment
  if (eta != null) {
    final minutes = eta.inMinutes;
    final seconds = eta.inSeconds % 60;
    segments.add('~${minutes}m ${seconds}s');
  }

  return segments.join(' · ');
}

import '../models/download_progress.dart';
import '../models/track.dart';

/// A snapshot of a single in-progress download enriched with a resolved
/// [Track], derived total bytes, live speed, and ETA.
class QueueItemView {
  final DownloadProgress progress;
  final Track? track;
  final int? totalBytes;
  final double? speedBytesPerSec;
  final Duration? eta;
  final String? error;

  const QueueItemView({
    required this.progress,
    this.track,
    this.totalBytes,
    this.speedBytesPerSec,
    this.eta,
    this.error,
  });
}

/// A bytes-at-time snapshot used to compute per-second speed between polls.
class Sample {
  final int bytes;
  final int atMs;
  const Sample(this.bytes, this.atMs);
}

/// Computes an enriched [QueueItemView] list from raw [DownloadProgress] items.
///
/// [items]  — latest snapshot from the backend poll.
/// [labels] — map of itemId → Track built by [downloadLabelsProvider].
/// [prev]   — sample map from the *previous* call (empty on first call).
/// [nowMs]  — current wall-clock in milliseconds.
///
/// Returns a record with:
/// - [views]: one enriched [QueueItemView] per item.
/// - [next]:  new sample map to pass as [prev] on the next call.
({List<QueueItemView> views, Map<String, Sample> next}) computeQueueView({
  required List<DownloadProgress> items,
  required Map<String, Track> labels,
  required Map<String, Sample> prev,
  required int nowMs,
}) {
  final views = <QueueItemView>[];
  final next = <String, Sample>{};

  for (final item in items) {
    final itemId = item.itemId;
    final track = labels[itemId];

    // Prefer backend-reported total; fall back to deriving from progress ratio.
    final int? totalBytes = item.bytesTotal > 0
        ? item.bytesTotal
        : (item.progress > 0 && item.bytesReceived > 0)
            ? (item.bytesReceived / item.progress).round()
            : null;

    // Compute speed if we have a previous sample with a positive time delta
    // and a positive bytes delta.
    double? speed;
    Duration? eta;
    final prevSample = prev[itemId];
    if (prevSample != null) {
      final timeDeltaMs = nowMs - prevSample.atMs;
      final bytesDelta = item.bytesReceived - prevSample.bytes;
      if (timeDeltaMs > 0 && bytesDelta > 0) {
        speed = bytesDelta / (timeDeltaMs / 1000.0);
        if (totalBytes != null && speed > 0) {
          final remaining = totalBytes - item.bytesReceived;
          eta = Duration(
            seconds: (remaining / speed).round().clamp(0, 86400),
          );
        }
      }
    }

    // Always record a new sample for this item.
    next[itemId] = Sample(item.bytesReceived, nowMs);

    views.add(QueueItemView(
      progress: item,
      track: track,
      totalBytes: totalBytes,
      speedBytesPerSec: speed,
      eta: eta,
    ));
  }

  return (views: views, next: next);
}

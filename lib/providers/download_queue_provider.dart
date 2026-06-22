import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/download_progress.dart';
import '../models/download_request.dart';
import '../models/track.dart';
import '../util/queue_view.dart';
import 'download_dir_provider.dart';
import 'download_labels_provider.dart';
import 'downloads_provider.dart';
import 'extensions_provider.dart';

// ---------------------------------------------------------------------------
// DownloadEntry — persistent client-side queue item
// ---------------------------------------------------------------------------

class DownloadEntry {
  final Track track;
  final String itemId;
  final String status;
  final double progress;
  final int bytesReceived;
  final int? totalBytes;
  final double? speedBytesPerSec;
  final Duration? eta;

  const DownloadEntry({
    required this.track,
    required this.itemId,
    required this.status,
    required this.progress,
    required this.bytesReceived,
    this.totalBytes,
    this.speedBytesPerSec,
    this.eta,
  });

  DownloadEntry copyWith({
    String? status,
    double? progress,
    int? bytesReceived,
    int? totalBytes,
    double? speedBytesPerSec,
    Duration? eta,
  }) {
    return DownloadEntry(
      track: track,
      itemId: itemId,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      totalBytes: totalBytes ?? this.totalBytes,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      eta: eta ?? this.eta,
    );
  }
}

// ---------------------------------------------------------------------------
// DownloadQueueController — client-side persistent download queue
// ---------------------------------------------------------------------------

class DownloadQueueController extends Notifier<List<DownloadEntry>> {
  final Map<String, Sample> _samples = {};

  @override
  List<DownloadEntry> build() {
    // Keep the poll alive and merge live progress into our entries.
    ref.listen<AsyncValue<List<DownloadProgress>>>(
      downloadsProvider,
      (_, next) {
        next.whenData(_merge);
      },
    );
    return [];
  }

  Future<void> enqueue(Track track, {String? source, String? quality}) async {
    // Generate itemId synchronously so the entry can be prepended before any
    // await (making it visible in the queue immediately on tap).
    final itemId = 'dl_${DateTime.now().microsecondsSinceEpoch}_${track.id}';

    // Register label so QueueItem can resolve track from itemId.
    ref.read(downloadLabelsProvider.notifier).put(itemId, track);

    // Prepend entry — happens synchronously before the first await.
    state = [
      DownloadEntry(
        track: track,
        itemId: itemId,
        status: 'downloading',
        progress: 0,
        bytesReceived: 0,
      ),
      ...state,
    ];

    // Now resolve the output directory (async).
    final dir = await ref.read(downloadDirProvider.future);

    final req = DownloadRequest(
      trackName: track.name,
      artistName: track.artists,
      outputDir: dir,
      albumName: track.albumName,
      isrc: track.isrc,
      useExtensions: true,
      source: source,
      quality: quality,
      itemId: itemId,
    );

    try {
      final res = await ref.read(backendBridgeProvider).downloadByStrategy(req);
      final failed = res['success'] == false ||
          (res['error'] != null && '${res['error']}'.isNotEmpty) ||
          (res['status']?.toString().toLowerCase().contains('error') ?? false) ||
          (res['status']?.toString().toLowerCase().contains('fail') ?? false) ||
          (res['status']?.toString().toLowerCase().contains('cancel') ?? false);
      _setStatus(itemId, failed ? 'failed' : 'done',
          progressIfDone: failed ? null : 1.0);
    } catch (_) {
      _setStatus(itemId, 'failed');
    }
  }

  void retry(String itemId) {
    final entry = state.where((e) => e.itemId == itemId).firstOrNull;
    if (entry == null) return;
    _removeLocal(itemId);
    enqueue(entry.track);
  }

  void remove(String itemId) {
    _removeLocal(itemId);
    // Best-effort cancel — ignore errors.
    ref
        .read(backendBridgeProvider)
        .cancelDownload(itemId)
        .catchError((_) {});
  }

  void _merge(List<DownloadProgress> items) {
    if (state.isEmpty) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final byId = {for (final p in items) p.itemId: p};

    state = [
      for (final entry in state)
        _mergeEntry(entry, byId[entry.itemId], nowMs),
    ];
  }

  DownloadEntry _mergeEntry(
    DownloadEntry entry,
    DownloadProgress? p,
    int nowMs,
  ) {
    // Terminal entries stay as-is.
    if (entry.status == 'done' || entry.status == 'failed') return entry;
    // No matching backend progress yet — keep current state.
    if (p == null) return entry;

    // Derive total bytes from progress ratio.
    final int? totalBytes = (p.progress > 0 && p.bytesReceived > 0)
        ? (p.bytesReceived / p.progress).round()
        : entry.totalBytes;

    // Compute speed + ETA from samples.
    double? speed;
    Duration? eta;
    final prev = _samples[entry.itemId];
    if (prev != null) {
      final timeDeltaMs = nowMs - prev.atMs;
      final bytesDelta = p.bytesReceived - prev.bytes;
      if (timeDeltaMs > 0 && bytesDelta > 0) {
        speed = bytesDelta / (timeDeltaMs / 1000.0);
        if (totalBytes != null && speed > 0) {
          final remaining = totalBytes - p.bytesReceived;
          eta = Duration(
            seconds: (remaining / speed).round().clamp(0, 86400),
          );
        }
      }
    }
    _samples[entry.itemId] = Sample(p.bytesReceived, nowMs);

    // Map backend status string to our known keywords.
    final status = _mapStatus(p.status, fallback: entry.status);

    return entry.copyWith(
      status: status,
      progress: p.progress,
      bytesReceived: p.bytesReceived,
      totalBytes: totalBytes,
      speedBytesPerSec: speed,
      eta: eta,
    );
  }

  /// Maps a raw backend status string to a keyword understood by QueueItem's
  /// _resolveState: 'downloading' | 'finalizing' | 'done' | 'failed' | 'queued'.
  static String _mapStatus(String raw, {required String fallback}) {
    final s = raw.toLowerCase();
    if (s.contains('download')) { return 'downloading'; }
    if (s.contains('metadata') ||
        s.contains('finaliz') ||
        s.contains('process') ||
        s.contains('writ')) { return 'finalizing'; }
    if (s.contains('complet') || s.contains('done') || s.contains('success')) {
      return 'done';
    }
    if (s.contains('fail') || s.contains('error')) { return 'failed'; }
    if (s.contains('queue') || s.contains('pending') || s.contains('wait')) {
      return 'queued';
    }
    return fallback;
  }

  void _setStatus(String itemId, String status, {double? progressIfDone}) {
    state = [
      for (final e in state)
        if (e.itemId == itemId)
          e.copyWith(
            status: status,
            progress: progressIfDone ?? e.progress,
          )
        else
          e,
    ];
  }

  void _removeLocal(String itemId) {
    state = [for (final e in state) if (e.itemId != itemId) e];
    _samples.remove(itemId);
  }
}

final downloadQueueProvider =
    NotifierProvider<DownloadQueueController, List<DownloadEntry>>(
  DownloadQueueController.new,
);

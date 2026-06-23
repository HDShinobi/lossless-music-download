import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/download_progress.dart';
import '../models/download_request.dart';
import '../models/installed_extension.dart';
import '../models/track.dart';
import '../util/queue_view.dart';
import 'download_dir_provider.dart';
import 'download_labels_provider.dart';
import 'downloads_provider.dart';
import 'extensions_provider.dart';
import 'library_provider.dart';

// Sentinel used to short-circuit _processQueue when a duplicate is detected,
// allowing the finally block (_isProcessing = false) to still run.
class _DuplicateSkipped implements Exception {}

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

  /// Failure reason from the backend (shown on a failed item). Null otherwise.
  final String? error;

  /// Download intent — preserved so retry can re-enqueue with the same params.
  final String? service;
  final String? quality;

  const DownloadEntry({
    required this.track,
    required this.itemId,
    required this.status,
    required this.progress,
    required this.bytesReceived,
    this.totalBytes,
    this.speedBytesPerSec,
    this.eta,
    this.error,
    this.service,
    this.quality,
  });

  DownloadEntry copyWith({
    String? status,
    double? progress,
    int? bytesReceived,
    int? totalBytes,
    double? speedBytesPerSec,
    Duration? eta,
    String? error,
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
      error: error ?? this.error,
      service: service,
      quality: quality,
    );
  }
}

// ---------------------------------------------------------------------------
// DownloadQueueController — client-side persistent download queue
// ---------------------------------------------------------------------------

class DownloadQueueController extends Notifier<List<DownloadEntry>> {
  final Map<String, Sample> _samples = {};

  // Sequential download gate — mirrors SpotiFLAC's _processQueue() pattern.
  bool _isProcessing = false;

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

  Future<void> enqueue(Track track, {String? service, String? quality}) async {
    final itemId = 'dl_${DateTime.now().microsecondsSinceEpoch}_${track.id}';

    // Register label so QueueItem can resolve track from itemId.
    ref.read(downloadLabelsProvider.notifier).put(itemId, track);

    // Prepend synchronously — visible in the queue immediately on tap.
    state = [
      DownloadEntry(
        track: track,
        itemId: itemId,
        status: 'queued',
        progress: 0,
        bytesReceived: 0,
        service: service,
        quality: quality,
      ),
      ...state,
    ];

    // Kick sequential processor (no-op if already running).
    unawaited(_processQueue());
  }

  // Mirrors SpotiFLAC's _processQueue(): downloads one item at a time.
  Future<void> _processQueue() async {
    if (_isProcessing) return;
    final next = state.where((e) => e.status == 'queued').firstOrNull;
    if (next == null) return;

    _isProcessing = true;
    _setStatus(next.itemId, 'downloading');

    try {
      final dir = await ref.read(downloadDirProvider.future);
      final bridge = ref.read(backendBridgeProvider);
      final dlProviders = (ref.read(extensionsProvider).value ??
              const <InstalledExtension>[])
          .where((e) => e.enabled && e.hasDownloadProvider)
          .map((e) => e.id)
          .toList();

      try {
        final current = await bridge.getDownloadPriority();
        if (current.isEmpty && dlProviders.isNotEmpty) {
          await bridge.setDownloadPriority(dlProviders);
        }
      } catch (_) {}

      // Skip download if file already exists on disk (mirrors SpotiFLAC's
      // checkDuplicate preflight). Only checked when ISRC is known.
      if (next.track.isrc != null && next.track.isrc!.isNotEmpty) {
        try {
          final dup = await bridge.checkDuplicate(dir, next.track.isrc!);
          if (dup['exists'] == true) {
            _setStatus(next.itemId, 'done', progressIfDone: 1.0);
            ref.invalidate(libraryProvider);
            throw _DuplicateSkipped();
          }
        } on _DuplicateSkipped {
          rethrow;
        } catch (_) {
          // checkDuplicate failure is non-fatal — proceed with download.
        }
      }

      final resolvedService =
          (next.service != null && next.service!.isNotEmpty)
              ? next.service
              : (dlProviders.isNotEmpty ? dlProviders.first : null);

      String? spotifyId = next.track.id.isEmpty ? null : next.track.id;
      String? qobuzId;
      String? tidalId;
      if (next.track.id.startsWith('qobuz:')) {
        qobuzId = next.track.id.substring(6);
        spotifyId = null;
      } else if (next.track.id.startsWith('tidal:')) {
        tidalId = next.track.id.substring(6);
        spotifyId = null;
      }

      final req = DownloadRequest(
        trackName: next.track.name,
        artistName: next.track.artists,
        outputDir: dir,
        albumName: next.track.albumName,
        albumArtist: next.track.albumArtist,
        isrc: next.track.isrc,
        spotifyId: spotifyId,
        qobuzId: qobuzId,
        tidalId: tidalId,
        coverUrl: next.track.coverUrl,
        durationMs: next.track.durationMs,
        trackNumber: next.track.trackNumber,
        discNumber: next.track.discNumber,
        totalTracks: next.track.totalTracks,
        totalDiscs: next.track.totalDiscs,
        releaseDate: next.track.releaseDate,
        composer: next.track.composer,
        source: next.track.source,
        genre: next.track.genre,
        label: next.track.label,
        copyright: next.track.copyright,
        service: resolvedService,
        quality: next.quality,
        itemId: next.itemId,
      );

      final res = await bridge.downloadByStrategy(req);
      final failed = res['success'] == false ||
          (res['error'] != null && '${res['error']}'.isNotEmpty) ||
          (res['status']?.toString().toLowerCase().contains('error') ?? false) ||
          (res['status']?.toString().toLowerCase().contains('fail') ?? false) ||
          (res['status']?.toString().toLowerCase().contains('cancel') ?? false);
      final err = res['error']?.toString() ?? res['error_type']?.toString();
      _setStatus(
        next.itemId,
        failed ? 'failed' : 'done',
        progressIfDone: failed ? null : 1.0,
        error: failed ? (err?.isNotEmpty == true ? err : 'unknown') : null,
      );
      if (!failed) ref.invalidate(libraryProvider);
    } on _DuplicateSkipped {
      // Item skipped — status already set to done above.
    } catch (e) {
      _setStatus(next.itemId, 'failed', error: e.toString());
    } finally {
      _isProcessing = false;
      // Process the next queued item (if any).
      unawaited(_processQueue());
    }
  }

  void retry(String itemId) {
    final entry = state.where((e) => e.itemId == itemId).firstOrNull;
    if (entry == null) return;
    _removeLocal(itemId);
    unawaited(enqueue(entry.track, service: entry.service, quality: entry.quality));
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

  void _setStatus(String itemId, String status,
      {double? progressIfDone, String? error}) {
    state = [
      for (final e in state)
        if (e.itemId == itemId)
          e.copyWith(
            status: status,
            progress: progressIfDone ?? e.progress,
            error: error,
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

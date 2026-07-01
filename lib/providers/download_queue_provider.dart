import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/download_progress.dart';
import '../models/download_request.dart';
import '../models/installed_extension.dart';
import '../models/track.dart';
import '../services/backend_bridge.dart';
import '../services/ffmpeg_metadata_service.dart';
import '../services/native_download_worker.dart';
import '../util/queue_view.dart';
import '../widgets/track_tile.dart'; // TrackDownloadState
import 'download_dir_provider.dart';
import 'download_labels_provider.dart';
import 'download_options_provider.dart';
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

  // Mirrors SpotiFLAC's _processQueue(): downloads queued items, preferring
  // the native background worker (Android) and falling back to the
  // Dart-only path for anything the native worker can't run.
  Future<void> _processQueue() async {
    if (_isProcessing) return;
    final queued = state.where((e) => e.status == 'queued').toList();
    if (queued.isEmpty) return;

    _isProcessing = true;
    try {
      final worker = ref.read(nativeDownloadWorkerProvider);
      if (worker.isAvailable) {
        await _runNativeBatch(worker, queued);
      } else {
        await _runDartFallback(queued.first);
      }
    } finally {
      _isProcessing = false;
      unawaited(_processQueue());
    }
  }

  Future<Map<String, dynamic>?> _buildRequestJson(DownloadEntry entry) async {
    final dir = await ref.read(downloadDirProvider.future);
    final dlProviders = (ref.read(extensionsProvider).value ??
            const <InstalledExtension>[])
        .where((e) => e.enabled && e.hasDownloadProvider)
        .map((e) => e.id)
        .toList();

    // Seed provider priority if it's never been set, same as the existing
    // Dart fallback path does per-item -- cheap/idempotent to repeat here.
    try {
      final bridge = ref.read(backendBridgeProvider);
      final current = await bridge.getDownloadPriority();
      if (current.isEmpty && dlProviders.isNotEmpty) {
        await bridge.setDownloadPriority(dlProviders);
      }
    } catch (_) {}

    final resolvedService = (entry.service != null && entry.service!.isNotEmpty)
        ? entry.service
        : (dlProviders.isNotEmpty ? dlProviders.first : null);

    String? spotifyId = entry.track.id.isEmpty ? null : entry.track.id;
    String? qobuzId;
    String? tidalId;
    if (entry.track.id.startsWith('qobuz:')) {
      qobuzId = entry.track.id.substring(6);
      spotifyId = null;
    } else if (entry.track.id.startsWith('tidal:')) {
      tidalId = entry.track.id.substring(6);
      spotifyId = null;
    }

    final req = DownloadRequest(
      trackName: entry.track.name,
      artistName: entry.track.artists,
      outputDir: dir,
      albumName: entry.track.albumName,
      albumArtist: entry.track.albumArtist,
      isrc: entry.track.isrc,
      spotifyId: spotifyId,
      qobuzId: qobuzId,
      tidalId: tidalId,
      coverUrl: entry.track.coverUrl,
      durationMs: entry.track.durationMs,
      trackNumber: entry.track.trackNumber,
      discNumber: entry.track.discNumber,
      totalTracks: entry.track.totalTracks,
      totalDiscs: entry.track.totalDiscs,
      releaseDate: entry.track.releaseDate,
      composer: entry.track.composer,
      source: entry.track.source,
      genre: entry.track.genre,
      label: entry.track.label,
      copyright: entry.track.copyright,
      service: resolvedService,
      quality: entry.quality,
      itemId: entry.itemId,
      embedMetadata: ref.read(embedMetadataProvider),
      embedMaxQualityCover: ref.read(embedCoverProvider),
      embedLyrics: ref.read(embedLyricsProvider),
    );
    return req.toJson();
  }

  Future<void> _runNativeBatch(
    NativeDownloadWorker worker,
    List<DownloadEntry> queued,
  ) async {
    final requests = <Map<String, dynamic>>[];
    final byItemId = {for (final e in queued) e.itemId: e};
    for (final entry in queued) {
      final json = await _buildRequestJson(entry);
      if (json == null || json['track_name'] == null || json['output_dir'] == null) {
        continue; // gate rejected -- handled by the Dart fallback below
      }
      requests.add(buildNativeWorkerRequest(
        itemId: entry.itemId,
        trackName: entry.track.name,
        artistName: entry.track.artists,
        requestJson: json,
      ));
    }

    final gateRejected =
        queued.where((e) => !requests.any((r) => r['item_id'] == e.itemId)).toList();

    var fellBackToStartupTimeout = false;
    if (requests.isNotEmpty) {
      final runId = 'run_${DateTime.now().microsecondsSinceEpoch}';
      await worker.start(requests, runId: runId);

      // Poll until the native worker reports it's done with this run. If it
      // never even starts within 30s (matching upstream's startup timeout),
      // give up on native execution for this whole batch and fall back to
      // the Dart-only path for every item in it.
      final startedAt = DateTime.now();
      var started = false;
      // Tracks the last time we merged a valid snapshot; used together with
      // `startedAt` so the 30s stall watchdog covers both a run that never
      // starts and a run that goes silent mid-flight (e.g. sustained
      // getSnapshot() exceptions).
      var lastSeenAt = DateTime.now();
      while (true) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        NativeWorkerSnapshot? snapshot;
        try {
          snapshot = await worker.getSnapshot();
        } catch (_) {
          snapshot = null;
        }
        if (snapshot == null || snapshot.runId != runId) {
          final stalledSince = started ? lastSeenAt : startedAt;
          if (DateTime.now().difference(stalledSince) > const Duration(seconds: 30)) {
            fellBackToStartupTimeout = true;
            break;
          }
          continue;
        }
        started = true;
        lastSeenAt = DateTime.now();
        _mergeNativeSnapshot(snapshot, byItemId);
        if (!snapshot.isRunning) break;
      }
      ref.invalidate(libraryProvider);
    }

    final fallbackEntries = fellBackToStartupTimeout
        ? [...gateRejected, ...queued.where((e) => requests.any((r) => r['item_id'] == e.itemId))]
        : gateRejected;
    for (final entry in fallbackEntries) {
      await _runDartFallback(entry);
    }
  }

  void _mergeNativeSnapshot(
    NativeWorkerSnapshot snapshot,
    Map<String, DownloadEntry> byItemId,
  ) {
    if (!snapshot.items.any((i) => byItemId.containsKey(i.itemId))) return;
    state = [
      for (final entry in state)
        if (byItemId.containsKey(entry.itemId))
          _applyNativeItemState(
            entry,
            snapshot.items.firstWhere(
              (i) => i.itemId == entry.itemId,
              orElse: () => NativeWorkerItemState(
                itemId: entry.itemId,
                status: entry.status,
                progress: entry.progress,
                bytesReceived: entry.bytesReceived,
                bytesTotal: entry.totalBytes ?? 0,
              ),
            ),
          )
        else
          entry,
    ];
  }

  DownloadEntry _applyNativeItemState(DownloadEntry entry, NativeWorkerItemState item) {
    if (entry.status == 'done' || entry.status == 'failed') return entry;
    return entry.copyWith(
      status: item.status,
      progress: item.progress,
      bytesReceived: item.bytesReceived,
      totalBytes: item.bytesTotal > 0 ? item.bytesTotal : entry.totalBytes,
      error: item.error,
    );
  }

  // The original single-item Dart download path -- now the fallback used
  // for non-Android platforms and any item the native worker's gate rejects.
  Future<void> _runDartFallback(DownloadEntry next) async {
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

      final embedMetadata = ref.read(embedMetadataProvider);
      final embedCover = ref.read(embedCoverProvider);
      final embedLyrics = ref.read(embedLyricsProvider);

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
        embedMetadata: embedMetadata,
        embedMaxQualityCover: embedCover,
        embedLyrics: embedLyrics,
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
      if (!failed) {
        // FLAC is tagged natively in the Go backend. Non-FLAC downloads
        // (Opus/M4A/MP3) are tagged here via FFmpeg.
        await _embedNonFlacMetadata(
          bridge: bridge,
          res: res,
          track: next.track,
          embedMetadata: embedMetadata,
          embedCover: embedCover,
          embedLyrics: embedLyrics,
        );
        ref.invalidate(libraryProvider);
      }
    } on _DuplicateSkipped {
      // Item skipped — status already set to done above.
    } catch (e) {
      _setStatus(next.itemId, 'failed', error: e.toString());
    }
  }

  /// Tags a freshly downloaded NON-FLAC file (Opus/M4A/MP3) via FFmpeg. FLAC is
  /// handled natively in the Go backend, so this is a no-op for FLAC.
  Future<void> _embedNonFlacMetadata({
    required BackendBridge bridge,
    required Map<String, dynamic> res,
    required Track track,
    required bool embedMetadata,
    required bool embedCover,
    required bool embedLyrics,
  }) async {
    if (!embedMetadata) return;
    final filePath = res['file_path']?.toString() ?? '';
    if (filePath.isEmpty ||
        filePath.startsWith('content://') ||
        filePath.startsWith('/proc/self/fd/') ||
        !FfmpegMetadataService.isNonFlacEmbeddable(filePath)) {
      return;
    }
    if (!await File(filePath).exists()) return;

    final metadata = <String, String>{
      if (track.name.isNotEmpty) 'TITLE': track.name,
      if (track.artists.isNotEmpty) 'ARTIST': track.artists,
      if ((track.albumName ?? '').isNotEmpty) 'ALBUM': track.albumName!,
      if ((track.albumArtist ?? '').isNotEmpty) 'ALBUMARTIST': track.albumArtist!,
      if ((track.releaseDate ?? '').isNotEmpty) 'DATE': track.releaseDate!,
      if ((track.isrc ?? '').isNotEmpty) 'ISRC': track.isrc!,
      if ((track.genre ?? '').isNotEmpty) 'GENRE': track.genre!,
      if ((track.label ?? '').isNotEmpty) 'ORGANIZATION': track.label!,
      if ((track.copyright ?? '').isNotEmpty) 'COPYRIGHT': track.copyright!,
      if ((track.composer ?? '').isNotEmpty) 'COMPOSER': track.composer!,
      if ((track.trackNumber ?? 0) > 0) 'TRACKNUMBER': '${track.trackNumber}',
      if ((track.discNumber ?? 0) > 0) 'DISCNUMBER': '${track.discNumber}',
    };

    if (embedLyrics) {
      try {
        final isProviderId =
            track.id.startsWith('qobuz:') || track.id.startsWith('tidal:');
        final lrc = await bridge.getLyricsLRC(
          spotifyId: isProviderId ? '' : track.id,
          trackName: track.name,
          artistName: track.artists,
          durationMs: track.durationMs ?? 0,
        );
        final trimmed = lrc.trim();
        if (trimmed.isNotEmpty && trimmed != '[instrumental:true]') {
          metadata['LYRICS'] = trimmed;
        }
      } catch (_) {
        // Lyrics are best-effort; ignore failures.
      }
    }

    String? coverPath;
    if (embedCover && (track.coverUrl ?? '').isNotEmpty) {
      coverPath = await _downloadCoverToTemp(track.coverUrl!);
    }

    try {
      await FfmpegMetadataService.embed(
        filePath: filePath,
        metadata: metadata,
        coverPath: coverPath,
      );
    } catch (_) {
      // Embedding failure is non-fatal — the file is still downloaded.
    } finally {
      if (coverPath != null) {
        try {
          await File(coverPath).delete();
        } catch (_) {}
      }
    }
  }

  /// Downloads a cover image to a temp file. Returns the path, or null on error.
  Future<String?> _downloadCoverToTemp(String url) async {
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return null;
      final dir = await getTemporaryDirectory();
      final ext = url.toLowerCase().contains('.png') ? '.png' : '.jpg';
      final path =
          '${dir.path}${Platform.pathSeparator}cover_${DateTime.now().microsecondsSinceEpoch}$ext';
      await File(path).writeAsBytes(resp.bodyBytes);
      return path;
    } catch (_) {
      return null;
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

  /// Returns the download state for a track by its [trackId].
  /// If the track has multiple entries, active/queued entries take priority
  /// over terminal (done/failed) entries.
  TrackDownloadState stateForTrack(String trackId) {
    final matches = state.where((e) => e.track.id == trackId);
    if (matches.isEmpty) return TrackDownloadState.idle;
    // Prefer the active entry if any.
    final active = matches.firstWhere(
      (e) => e.status == 'queued' ||
          e.status == 'downloading' ||
          e.status == 'finalizing',
      orElse: () => matches.first,
    );
    return switch (active.status) {
      'queued' => TrackDownloadState.queued,
      'downloading' || 'finalizing' => TrackDownloadState.active,
      'done' => TrackDownloadState.done,
      'failed' => TrackDownloadState.failed,
      _ => TrackDownloadState.idle,
    };
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

final nativeDownloadWorkerProvider =
    Provider<NativeDownloadWorker>((ref) => NativeDownloadWorker());

final downloadQueueProvider =
    NotifierProvider<DownloadQueueController, List<DownloadEntry>>(
  DownloadQueueController.new,
);

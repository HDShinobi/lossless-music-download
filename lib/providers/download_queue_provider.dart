import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../l10n/app_localizations.dart';
import '../models/download_progress.dart';
import '../models/download_request.dart';
import '../models/installed_extension.dart';
import '../models/track.dart';
import '../services/app_log.dart';
import '../services/backend_bridge.dart';
import '../services/container_remux_service.dart';
import '../services/download_templates.dart';
import '../services/ffmpeg_metadata_service.dart';
import '../services/native_download_worker.dart';
import '../services/history_database.dart';
import '../util/queue_view.dart';
import '../utils/extension_auth_launcher.dart';
import '../widgets/track_tile.dart'; // TrackDownloadState
import 'download_dir_provider.dart';
import 'download_history_provider.dart';
import 'download_labels_provider.dart';
import 'download_options_provider.dart';
import 'downloads_provider.dart';
import 'extensions_provider.dart';
import 'library_provider.dart';
import 'locale_provider.dart';

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

  /// Extension that raised a verification_required error, as reported by the
  /// backend result's `service` field. May differ from [service] when the
  /// error came from a fallback provider (e.g. qobuz-web behind amazon).
  final String? verificationService;

  /// The provider that actually delivered the file (from the backend result's
  /// `service`). Differs from [service] when a fallback provider won.
  final String? resolvedService;

  final String? filePath;
  final bool alreadyInLibrary;
  final bool bypassDuplicateCheck;

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
    this.verificationService,
    this.resolvedService,
    this.filePath,
    this.alreadyInLibrary = false,
    this.bypassDuplicateCheck = false,
  });

  DownloadEntry copyWith({
    String? status,
    double? progress,
    int? bytesReceived,
    int? totalBytes,
    double? speedBytesPerSec,
    Duration? eta,
    String? error,
    String? verificationService,
    String? resolvedService,
    String? filePath,
    bool? alreadyInLibrary,
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
      error: alreadyInLibrary == true ? null : error ?? this.error,
      service: service,
      quality: quality,
      verificationService: verificationService ?? this.verificationService,
      resolvedService: resolvedService ?? this.resolvedService,
      filePath: filePath ?? this.filePath,
      alreadyInLibrary: alreadyInLibrary ?? this.alreadyInLibrary,
      bypassDuplicateCheck: bypassDuplicateCheck,
    );
  }
}

// ---------------------------------------------------------------------------
// DownloadQueueController — client-side persistent download queue
// ---------------------------------------------------------------------------

final nativeQueueLabelsProvider = Provider<Map<String, String>>((ref) {
  final locale = ref.watch(localeProvider);
  final t = lookupAppLocalizations(locale);
  return {'paused_label': t.queuePaused, 'waiting_wifi_label': t.queueWaitingWifi,
    'pause_label': t.queuePause, 'resume_label': t.queueResume};
});

class QueuePauseReasonNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? value) => state = value;
}

final queuePauseReasonProvider = NotifierProvider<QueuePauseReasonNotifier, String?>(
  QueuePauseReasonNotifier.new,
);

/// Only offer a duplicate override when the current target moves the file.
final canDownloadAnywayProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  itemId,
) async {
  final entry = ref.watch(downloadQueueProvider.select(
    (entries) => entries.where((e) => e.itemId == itemId).firstOrNull,
  ));
  if (entry == null ||
      !entry.alreadyInLibrary ||
      entry.filePath == null ||
      entry.filePath!.isEmpty) {
    return false;
  }
  final directory = ref.watch(downloadDirProvider.future);
  ref.watch(folderOrganizationProvider);
  ref.watch(filenameTemplateProvider);
  ref.watch(albumFolderTemplateProvider);
  await Future.wait([
    ref.read(folderOrganizationProvider.notifier).ready,
    ref.read(filenameTemplateProvider.notifier).ready,
    ref.read(albumFolderTemplateProvider.notifier).ready,
  ]);
  final dir = await directory;
  if (!ref.mounted) return false;
  final target = ref
      .read(downloadQueueProvider.notifier)
      ._resolveOutputTarget(dir, entry.track, quality: entry.quality);
  // DownloadRequest leaves output_ext unset: the engine's destination defaults
  // to .flac. A provider may report a different container after downloading.
  final basename = DownloadTemplates.preview(
    target.template,
    entry.track,
    quality: entry.quality,
  );
  final path = '${target.dir}/$basename.flac';
  return File(entry.filePath!).absolute.uri.normalizePath() !=
      File(path).absolute.uri.normalizePath();
});

class DownloadQueueController extends Notifier<List<DownloadEntry>> {
  final Map<String, Sample> _samples = {};
  final Map<String, Set<String>> _loggedLifecycleEvents = {};

  // One batch at a time; native execution owns per-item concurrency.
  bool _isProcessing = false;
  bool _nativeRunStopped = false;
  bool _manualPaused = false;
  bool? _pendingPause;
  NativeDownloadWorker? _activeWorker;

  Future<void> pause() async {
    _manualPaused = true;
    _pendingPause = true;
    ref.read(queuePauseReasonProvider.notifier).set('paused');
    await _activeWorker?.pause();
  }

  Future<void> resume() async {
    _manualPaused = false;
    _pendingPause = false;
    ref.read(queuePauseReasonProvider.notifier).set(null);
    await _activeWorker?.resume();
    if (ref.mounted) unawaited(_processQueue());
  }

  void clearCompleted() {
    for (final entry in state.where((e) => e.status == 'done').toList()) {
      _removeLocal(entry.itemId);
    }
  }

  void retryAllFailed() {
    for (final entry in state.where((e) => e.status == 'failed').toList()) {
      retry(entry.itemId);
    }
  }

  Future<bool> _waitForAdmission(String itemId) async {
    while (ref.mounted && state.any((e) => e.itemId == itemId)) {
      final allowed = !ref.read(wifiOnlyProvider) ||
          await ref.read(downloadNetworkAllowedProvider.future);
      if (!ref.mounted || !state.any((e) => e.itemId == itemId)) return false;
      ref.read(queuePauseReasonProvider.notifier).set(
        _manualPaused ? 'paused' : !allowed ? 'waiting_wifi' : null);
      if (!_manualPaused && allowed) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (ref.mounted) ref.invalidate(downloadNetworkAllowedProvider);
    }
    return false;
  }

  // Items already given one rate-limit (HTTP 429) backoff retry. Mirrors
  // SpotiFLAC's _rateLimitRetriedItemIds — one delayed retry per item, then
  // the failure is surfaced.
  final Set<String> _rateLimitRetriedItemIds = {};

  @override
  List<DownloadEntry> build() {
    final lifecycle = AppLifecycleListener(onResume: () {
      if (ref.mounted) unawaited(_processQueue());
    });
    ref.onDispose(lifecycle.dispose);
    // Keep the poll alive and merge live progress into our entries.
    ref.listen<AsyncValue<List<DownloadProgress>>>(
      downloadsProvider,
      (_, next) {
        next.whenData(_merge);
      },
    );
    return [];
  }

  Future<void> enqueue(Track track, {String? service, String? quality,
      bool bypassDuplicateCheck = false}) async {
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
        bypassDuplicateCheck: bypassDuplicateCheck,
      ),
      ...state,
    ];

    printAppLog(LogLevel.info, 'Queue',
        'Enqueued ${track.name} – ${track.artists}; service=${service ?? 'auto'}, quality=${quality ?? 'default'}');

    // Kick sequential processor (no-op if already running).
    unawaited(_processQueue());
  }

  // Mirrors SpotiFLAC's _processQueue(): downloads queued items, preferring
  // the native background worker (Android) and falling back to the
  // Dart-only path for anything the native worker can't run.
  Future<void> _processQueue() async {
    if (!ref.mounted || _isProcessing || _manualPaused) return;
    final queued = state.where((e) => e.status == 'queued').toList();
    if (queued.isEmpty) return;

    _isProcessing = true;
    _nativeRunStopped = false;
    var continueProcessing = true;
    try {
      // Hydrate every option before resolving paths or building either kind of
      // request. These notifiers expose defaults until their startup load ends.
      await Future.wait([
        ref.read(folderOrganizationProvider.notifier).ready,
        ref.read(filenameTemplateProvider.notifier).ready,
        ref.read(albumFolderTemplateProvider.notifier).ready,
        ref.read(artistTagModeProvider.notifier).ready,
        ref.read(metadataSeparatorsProvider.notifier).ready,
        ref.read(embedMetadataProvider.notifier).ready,
        ref.read(embedCoverProvider.notifier).ready,
        ref.read(embedLyricsProvider.notifier).ready,
        ref.read(autoFallbackProvider.notifier).ready,
        ref.read(writeLrcSidecarProvider.notifier).ready,
        ref.read(simultaneousDownloadsProvider.notifier).ready,
        ref.read(wifiOnlyProvider.notifier).ready,
      ]);
      if (!ref.mounted || _manualPaused) return;
      final worker = ref.read(nativeDownloadWorkerProvider);
      final admitted = worker.isAvailable ? await _historyPrecheck(queued) : queued;
      if (!ref.mounted || admitted.isEmpty) return;
      if (worker.isAvailable) {
        continueProcessing = await _runNativeBatch(worker, admitted);
      } else {
        await _runDartFallback(admitted.first);
      }
    } finally {
      _isProcessing = false;
      if (ref.mounted && continueProcessing) unawaited(_processQueue());
    }
  }

  Future<List<DownloadEntry>> _historyPrecheck(List<DownloadEntry> entries) async {
    try {
      final db = await ref.read(historyDatabaseProvider.future);
      final matches = await db.findBatch(entries.map((e) => e.track).toList(), strict: true);
      if (!ref.mounted) return [];
      final admitted = <DownloadEntry>[];
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        if (!state.any((e) => e.itemId == entry.itemId && e.status != 'done' && e.status != 'failed')) continue;
        final match = matches[i];
        if (entry.bypassDuplicateCheck || match == null) {
          admitted.add(entry);
        } else {
          _setStatus(entry.itemId, 'done', progressIfDone: 1,
              filePath: match.filePath, alreadyInLibrary: true);
        }
      }
      return admitted;
    } catch (e) {
      // Storage failure must not prevent downloading. The engine's existing
      // ISRC/IndexCache check still runs in both execution paths.
      debugPrint('[DownloadQueue] history precheck unavailable: $e');
      return entries;
    }
  }

  Future<bool> _skipIndexedDuplicate(DownloadEntry entry, String directory) async {
    if (entry.bypassDuplicateCheck) return false;
    final isrc = entry.track.isrc;
    if (isrc == null || isrc.isEmpty) return false;
    try {
      final duplicate = await ref.read(backendBridgeProvider).checkDuplicate(directory, isrc);
      if (!ref.mounted || duplicate['exists'] != true) return false;
      final path = (duplicate['filepath'] ?? duplicate['path'])?.toString();
      _setStatus(entry.itemId, 'done', progressIfDone: 1,
        filePath: path, alreadyInLibrary: true);
      await _recordCompletedHistory([entry.copyWith(status: 'done',
        filePath: path, alreadyInLibrary: true)]);
      return true;
    } catch (_) { return false; }
  }

  final Map<String, String> _recordedHistory = {};
  Future<void> _recordCompletedHistory(Iterable<DownloadEntry> entries) async {
    for (final entry in entries.where((e) => e.status == 'done')) {
      final path = entry.filePath;
      if (path == null || path.isEmpty) continue;
      final service = [entry.resolvedService, entry.service, entry.track.source]
          .whereType<String>().where((s) => s.isNotEmpty).firstOrNull ?? '';
      final fingerprint = '$path|$service';
      if (_recordedHistory[entry.itemId] == fingerprint) continue;
      try {
        final db = await ref.read(historyDatabaseProvider.future);
        final stat = await File(path).stat();
        await db.upsert(HistoryEntry(id: entry.itemId, track: entry.track,
          service: service, filePath: path,
          fileSize: stat.type == FileSystemEntityType.file ? stat.size : null,
          quality: entry.quality, downloadedAt: DateTime.now()));
        _recordedHistory[entry.itemId] = fingerprint;
        if (ref.mounted) ref.read(historyRevisionProvider.notifier).changed();
      } catch (e) {
        printAppLog(LogLevel.warning, 'Queue', 'History recording failed; item=${entry.itemId}; $e');
      }
    }
  }

  /// Resolves where a track is written and under what basename.
  ///
  /// Folders are the app's concern, not the engine's: the engine treats the
  /// filename template as a single basename and flattens any `/` in it (see
  /// [buildRelativeFolder]), so we resolve the directory here and hand it a flat
  /// template. Pure by design — the engine `MkdirAll`s whatever `outputDir` it
  /// receives, so creating it here would only add filesystem I/O to the enqueue
  /// path.
  ({String dir, String template}) _resolveOutputTarget(
    String baseDir,
    Track track, {
    String? quality,
  }) {
    return resolveDownloadTarget(baseDir, track,
      mode: ref.read(folderOrganizationProvider),
      filenameTemplate: ref.read(filenameTemplateProvider),
      albumFolderTemplate: ref.read(albumFolderTemplateProvider),
      quality: quality);
  }

  static String _yearOf(String? releaseDate) {
    final d = releaseDate?.trim() ?? '';
    return d.length >= 4 ? d.substring(0, 4) : '';
  }

  /// Whether to ask for a container we can read as lossless: only meaningful
  /// when the user picked a FLAC tier *and* the chosen source is known to wrap
  /// FLAC in MP4. Mirrors SpotiFLAC's _shouldRequestContainerConversion.
  bool _wantsContainerConversion(String? service, String? quality) {
    final q = (quality ?? '').toLowerCase();
    if (!q.contains('flac') && !q.contains('lossless')) return false;
    final id = (service ?? '').trim().toLowerCase();
    if (id.isEmpty) return false;
    final exts = ref.read(extensionsProvider).value ?? const <InstalledExtension>[];
    return exts.any((e) =>
        e.enabled &&
        e.hasDownloadProvider &&
        e.id.toLowerCase() == id &&
        e.requiresContainerConversion);
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

    final target = _resolveOutputTarget(dir, entry.track, quality: entry.quality);

    final req = DownloadRequest(
      trackName: entry.track.name,
      artistName: entry.track.artists,
      outputDir: target.dir,
      filenameFormat: target.template,
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
      explicit: entry.track.explicit,
      upc: entry.track.upc,
      albumType: entry.track.albumType,
      deezerId: entry.track.deezerId,
      playlistPosition: entry.track.playlistPosition,
      service: resolvedService,
      quality: entry.quality,
      itemId: entry.itemId,
      requiresContainerConversion:
          _wantsContainerConversion(resolvedService, entry.quality),
      embedMetadata: ref.read(embedMetadataProvider),
      embedMaxQualityCover: ref.read(embedCoverProvider),
      embedLyrics: ref.read(embedLyricsProvider),
      useFallback: ref.read(autoFallbackProvider),
      artistTagMode: ref.read(artistTagModeProvider),
      metadataSeparators: ref.read(metadataSeparatorsProvider),
      writeLrcSidecar: ref.read(writeLrcSidecarProvider),
    );
    final provider = (ref.read(extensionsProvider).value ?? const <InstalledExtension>[])
        .where((e) => e.id == resolvedService).firstOrNull;
    return {...req.toJson(),
      if (entry.bypassDuplicateCheck) 'bypass_duplicate_check': true,
      'network_concurrency_limit': provider?.maxConcurrentDownloads ?? 3};
  }

  Future<bool> _runNativeBatch(
    NativeDownloadWorker worker,
    List<DownloadEntry> queued,
  ) async {
    final requests = <Map<String, dynamic>>[];
    final byItemId = {for (final e in queued) e.itemId: e};
    var skippedDuplicate = false;
    for (final entry in queued) {
      final json = await _buildRequestJson(entry);
      if (json == null || json['track_name'] == null || json['output_dir'] == null) {
        continue; // gate rejected -- handled by the Dart fallback below
      }
      // Retain the engine index as a secondary signal, and capture its path
      // here: the native duplicate status alone does not carry a file_path.
      if (await _skipIndexedDuplicate(entry, json['output_dir'] as String)) {
        skippedDuplicate = true;
        continue;
      }
      if (!ref.mounted || !state.any((e) => e.itemId == entry.itemId)) continue;
      requests.add(buildNativeWorkerRequest(
        itemId: entry.itemId,
        trackName: entry.track.name,
        artistName: entry.track.artists,
        requestJson: json,
      ));
    }

    if (skippedDuplicate && ref.mounted) ref.invalidate(libraryProvider);

    final gateRejected =
        queued.where((e) => !requests.any((r) => r['item_id'] == e.itemId) &&
          state.any((current) => current.itemId == e.itemId && current.status != 'done')).toList();

    var fellBackToStartupTimeout = false;
    var stoppedWithPending = false;
    if (requests.isNotEmpty) {
      final runId = 'run_${DateTime.now().microsecondsSinceEpoch}';
      printAppLog(LogLevel.debug, 'Queue', 'Starting native batch: ${requests.length} items');
      await worker.start(requests, runId: runId, settings: {
        'concurrent_downloads': ref.read(simultaneousDownloadsProvider),
        'wifi_only': ref.read(wifiOnlyProvider),
        'is_paused': _manualPaused,
        // Notification labels come from the same selected locale as queue UI.
        ...ref.read(nativeQueueLabelsProvider),
      });
      _activeWorker = worker;
      if (_manualPaused) await worker.pause();

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
      while (ref.mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!ref.mounted) return false;
        NativeWorkerSnapshot? snapshot;
        try {
          snapshot = await worker.getSnapshot();
        } catch (e) {
          debugPrint('[DownloadQueue] getSnapshot() failed: $e');
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
        await _recordCompletedHistory(byItemId.values);
        // Native publishes done + final file_path together before its final
        // non-running snapshot; progress-only done may arrive earlier.
        if (!snapshot.isRunning) {
          stoppedWithPending = snapshot.items.any((i) =>
              byItemId.containsKey(i.itemId) && i.status == 'queued');
          _nativeRunStopped = stoppedWithPending;
          break;
        }
      }
      _activeWorker = null;
      if (!ref.mounted) return false;
      for (final id in byItemId.keys) {
        if (!state.any((e) => e.itemId == id)) _recordedHistory.remove(id);
      }
      ref.read(queuePauseReasonProvider.notifier).set(_manualPaused ? 'paused' : null);
      ref.invalidate(libraryProvider);
    }

    final fallbackEntries = fellBackToStartupTimeout
        ? [...gateRejected, ...queued.where((e) => requests.any((r) => r['item_id'] == e.itemId))]
        : gateRejected;
    for (final entry in fallbackEntries) {
      await _runDartFallback(entry, historyChecked: true);
    }
    return !stoppedWithPending;
  }

  void _mergeNativeSnapshot(
    NativeWorkerSnapshot snapshot,
    Map<String, DownloadEntry> byItemId,
  ) {
    final nativeManualPause = snapshot.pauseReason == 'paused';
    if (_pendingPause == nativeManualPause) _pendingPause = null;
    if (_pendingPause == null) _manualPaused = nativeManualPause;
    ref.read(queuePauseReasonProvider.notifier).set(_manualPaused
        ? 'paused' : snapshot.pauseReason == 'waiting_wifi' ? 'waiting_wifi' : null);
    if (!snapshot.items.any((i) => byItemId.containsKey(i.itemId))) return;
    // Run-owned entries outlive cleared UI rows, so a late final path still
    // reaches history. Only entries still visible are published to queue UI.
    final visible = {for (final entry in state) entry.itemId: entry};
    for (final item in snapshot.items) {
      final entry = visible[item.itemId] ?? byItemId[item.itemId];
      if (entry != null && byItemId.containsKey(item.itemId)) {
        byItemId[item.itemId] = _applyNativeItemState(entry, item);
      }
    }
    state = [for (final entry in state) byItemId[entry.itemId] ?? entry];

    // Native worker reported a rate-limit (HTTP 429) failure — give it one
    // delayed retry so the shared API's limit resets, instead of hard-failing.
    for (final e in state) {
      if (e.status == 'failed' &&
          isRateLimitError(e.error) &&
          !_rateLimitRetriedItemIds.contains(e.itemId)) {
        unawaited(_handleRateLimited(e.itemId, e.error ?? ''));
      }
    }
  }

  DownloadEntry _applyNativeItemState(DownloadEntry entry, NativeWorkerItemState item) {
    // Late terminal snapshots may supply the error/service missing in progress.
    if ((entry.status == 'done' || entry.status == 'failed') &&
        entry.status != item.status &&
        !(entry.status == 'done' && _existingLibraryPath(item.error) != null)) {
      return entry;
    }
    final existingPath = item.status == 'failed'
        ? _existingLibraryPath(item.error)
        : null;
    final updated = entry.copyWith(
      status: existingPath != null ? 'done' : item.status,
      progress: existingPath != null ? 1.0 : item.progress,
      bytesReceived: item.bytesReceived,
      totalBytes: item.bytesTotal > 0 ? item.bytesTotal : entry.totalBytes,
      error: foldRetryAfterSeconds(item.error, item.retryAfterSeconds),
      verificationService: item.service,
      resolvedService: item.resolvedService,
      filePath: existingPath ?? item.filePath,
      alreadyInLibrary: existingPath != null ||
          (item.status == 'done' && item.alreadyExists) || entry.alreadyInLibrary,
    );
    _logTransition(entry, updated, filePath: updated.filePath);
    return updated;
  }

  // The original single-item Dart download path -- now the fallback used
  // for non-Android platforms, items the native worker's gate rejects, and
  // runs whose native snapshot stalls.
  Future<void> _runDartFallback(DownloadEntry next,
      {bool historyChecked = false}) async {
    if (!ref.mounted || !state.any((e) => e.itemId == next.itemId &&
        e.status != 'done' && e.status != 'failed')) {
      return;
    }
    if (!historyChecked && (await _historyPrecheck([next])).isEmpty) return;
    if (!ref.mounted) return;
    _setStatus(next.itemId, 'downloading');
    DownloadEntry? completed;
    try {
      if (!ref.mounted || !state.any((e) => e.itemId == next.itemId)) return;
      if (_manualPaused || ref.read(wifiOnlyProvider)) {
        _setStatus(next.itemId, 'queued');
        if (!await _waitForAdmission(next.itemId)) return;
        _setStatus(next.itemId, 'downloading');
      }
      printAppLog(LogLevel.debug, 'Queue', 'Starting Dart fallback: ${next.itemId}');
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

      final target = _resolveOutputTarget(dir, next.track, quality: next.quality);

      if (await _skipIndexedDuplicate(next, target.dir)) throw _DuplicateSkipped();

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
        outputDir: target.dir,
        filenameFormat: target.template,
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
        explicit: next.track.explicit,
        upc: next.track.upc,
        albumType: next.track.albumType,
        deezerId: next.track.deezerId,
        playlistPosition: next.track.playlistPosition,
        service: resolvedService,
        quality: next.quality,
        itemId: next.itemId,
        requiresContainerConversion:
            _wantsContainerConversion(resolvedService, next.quality),
        embedMetadata: embedMetadata,
        embedMaxQualityCover: embedCover,
        embedLyrics: embedLyrics,
        useFallback: ref.read(autoFallbackProvider),
        artistTagMode: ref.read(artistTagModeProvider),
        metadataSeparators: ref.read(metadataSeparatorsProvider),
        writeLrcSidecar: ref.read(writeLrcSidecarProvider),
      );

      final res = await bridge.downloadByStrategy(req);
      final failed = res['success'] == false ||
          (res['error'] != null && '${res['error']}'.isNotEmpty) ||
          (res['status']?.toString().toLowerCase().contains('error') ?? false) ||
          (res['status']?.toString().toLowerCase().contains('fail') ?? false) ||
          (res['status']?.toString().toLowerCase().contains('cancel') ?? false);
      final retryAfter = (res['retry_after_seconds'] as num?)?.toInt() ?? 0;
      final err = foldRetryAfterSeconds(
          res['error']?.toString() ?? res['error_type']?.toString(), retryAfter);
      final existingPath = failed
          ? _existingLibraryPath(res['error']?.toString())
          : null;
      if (existingPath != null) {
        completed = next.copyWith(status: 'done', filePath: existingPath, alreadyInLibrary: true);
        _setStatus(next.itemId, 'done', progressIfDone: 1.0,
            filePath: existingPath, alreadyInLibrary: true);
        ref.invalidate(libraryProvider);
        return;
      }
      final resultService = res['service']?.toString();
      if (failed &&
          isRateLimitError(err) &&
          await _handleRateLimited(next.itemId, err ?? '')) {
        return; // one delayed retry scheduled; don't surface the failure yet
      }
      if (!failed) {
        // Some sources (Amazon's FLAC tier) deliver a FLAC stream wrapped in
        // MP4. Unwrap it before tagging so it gets the FLAC path, not the lossy
        // one, and so the library reports it as lossless.
        await _unwrapMp4Flac(bridge: bridge, res: res, track: next.track);
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
        if (ref.read(writeLrcSidecarProvider)) {
          await _writeLrcSidecar(bridge, res, next.track);
        }
      }
      _setStatus(
        next.itemId,
        failed ? 'failed' : 'done',
        progressIfDone: failed ? null : 1.0,
        filePath: res['file_path']?.toString(),
        error: failed ? (err?.isNotEmpty == true ? err : 'unknown') : null,
        verificationService:
            failed && (resultService?.isNotEmpty ?? false) ? resultService : null,
        resolvedService:
            !failed && (resultService?.isNotEmpty ?? false) ? resultService : null,
      );
      if (!failed) {
        completed = next.copyWith(status: 'done', filePath: res['file_path']?.toString(),
          resolvedService: resultService);
        ref.invalidate(libraryProvider);
      }
    } on _DuplicateSkipped {
      // Item skipped — status already set to done above.
      if (ref.mounted) ref.invalidate(libraryProvider);
    } catch (e) {
      _setStatus(next.itemId, 'failed', error: e.toString());
    } finally {
      if (ref.mounted && completed != null) await _recordCompletedHistory([completed]);
    }
  }

  /// Decrypts an MP4-delivered download and unwraps its FLAC, rewriting
  /// `res['file_path']` in place so the tagging, sidecar and library steps that
  /// follow all see the finished file.
  ///
  /// The Go backend already skipped its native FLAC tagger for this download
  /// (the file was still MP4 at the time), so the result is tagged here.
  Future<void> _unwrapMp4Flac({
    required BackendBridge bridge,
    required Map<String, dynamic> res,
    required Track track,
  }) async {
    final flacPath = await ContainerRemuxService.finalizeDownload(res);
    if (flacPath == null) return; // nothing to decrypt/unwrap

    res['file_path'] = flacPath;
    debugPrint('[DownloadQueue] finalized MP4 download to: $flacPath');

    if (!flacPath.toLowerCase().endsWith('.flac')) return;
    if (!ref.read(embedMetadataProvider)) return;
    try {
      await bridge.editFileMetadata(flacPath, {
        'title': track.name,
        'artist': track.artists,
        if (track.albumName != null) 'album': track.albumName!,
        if (track.albumArtist != null) 'albumArtist': track.albumArtist!,
        if (track.trackNumber != null) 'trackNumber': '${track.trackNumber}',
        if (track.releaseDate != null) 'year': _yearOf(track.releaseDate),
        if (track.isrc != null) 'isrc': track.isrc!,
      });
    } catch (e) {
      // Tagging is a bonus; an untagged lossless file still beats ciphertext
      // labelled as hi-res, so never fail the download over it.
      debugPrint('[DownloadQueue] tagging finalized FLAC failed: $e');
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

  /// Writes a `.lrc` sidecar next to the downloaded file, using lyrics
  /// fetched online. Best-effort: never fails the download.
  Future<void> _writeLrcSidecar(
      BackendBridge bridge, Map<String, dynamic> res, Track track) async {
    try {
      final filePath = res['file_path']?.toString() ?? '';
      if (filePath.isEmpty ||
          filePath.startsWith('content://') ||
          filePath.startsWith('/proc/self/fd/')) {
        return;
      }
      if (!await File(filePath).exists()) return;
      final isProviderId =
          track.id.startsWith('qobuz:') || track.id.startsWith('tidal:');
      // CRITICAL: fetch ONLINE (no filePath). The Go GetLyricsLRC only reads
      // already-embedded lyrics when filePath is set and returns "" on miss —
      // and nothing is embedded yet at this point — so passing filePath here
      // would make the sidecar silently never write. Empty filePath = online.
      final lrc = await bridge.getLyricsLRC(
        spotifyId: isProviderId ? '' : track.id,
        trackName: track.name,
        artistName: track.artists,
        durationMs: track.durationMs ?? 0,
      );
      final trimmed = lrc.trim();
      if (trimmed.isEmpty || trimmed == '[instrumental:true]') return;
      // Strip only a real extension: the last '.' must come after the last '/'
      // (a dotted directory name with an extensionless file must not corrupt the path).
      final slash = filePath.lastIndexOf('/');
      final dot = filePath.lastIndexOf('.');
      final base = dot > slash ? filePath.substring(0, dot) : filePath;
      await File('$base.lrc').writeAsString(trimmed, encoding: utf8);
    } catch (_) {
      // Sidecar is best-effort; never fail the download.
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

  void retry(String itemId) => _requeue(itemId);

  void downloadAnyway(String itemId) => _requeue(itemId, bypassDuplicateCheck: true);

  void _requeue(String itemId, {bool bypassDuplicateCheck = false}) {
    final entry = state.where((e) => e.itemId == itemId).firstOrNull;
    if (entry == null) return;
    _removeLocal(itemId);
    unawaited(enqueue(entry.track, service: entry.service, quality: entry.quality,
      bypassDuplicateCheck: bypassDuplicateCheck));
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
    // Late engine progress cannot revive an item requeued by native stop.
    if (_nativeRunStopped && entry.status == 'queued') return entry;
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

    final updated = entry.copyWith(
      status: status,
      progress: p.progress,
      bytesReceived: p.bytesReceived,
      totalBytes: totalBytes,
      speedBytesPerSec: speed,
      eta: eta,
    );
    _logTransition(entry, updated);
    return updated;
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
      {double? progressIfDone, String? error, String? verificationService,
      String? resolvedService, String? filePath, bool? alreadyInLibrary}) {
    state = state.map((entry) {
      if (entry.itemId != itemId) return entry;
      final updated = entry.copyWith(
        status: status,
        progress: progressIfDone ?? entry.progress,
        error: error,
        verificationService: verificationService,
        resolvedService: resolvedService,
        filePath: filePath,
        alreadyInLibrary: alreadyInLibrary,
      );
      _logTransition(entry, updated, filePath: filePath);
      return updated;
    }).toList();
  }

  /// Logs terminal transitions once per attempt across progress/result paths.
  /// Completion progress has no path/service: log pending immediately. Failure
  /// logs wait for details to distinguish destination collisions from errors.
  void _logTransition(DownloadEntry before, DownloadEntry after,
      {String? filePath}) {
    if (before.status != after.status && after.status == 'queued') {
      // The automatic rate-limit retry reuses itemId for a new attempt.
      _loggedLifecycleEvents.remove(after.itemId);
    }
    if (after.status != 'done' && after.status != 'failed') return;
    final logged = _loggedLifecycleEvents.putIfAbsent(after.itemId, () => {});
    // Progress carries no error details. Wait for the result/snapshot so a
    // destination collision can become a duplicate skip without a Failed log.
    if (after.status == 'failed' && after.error == null) return;
    if (logged.add(after.status)) {
      if (after.status == 'done') {
        if (after.alreadyInLibrary) {
          printAppLog(LogLevel.info, 'Queue',
              'Duplicate skip; item=${after.itemId}; file=${after.filePath ?? 'pending'}');
        } else {
          final service = after.resolvedService?.isNotEmpty == true
              ? after.resolvedService : 'pending';
          printAppLog(LogLevel.info, 'Queue',
              'Completed service=$service; file=${filePath?.isNotEmpty == true ? filePath : 'pending'}');
        }
      } else {
        final service = after.verificationService ?? after.service ?? 'auto';
        printAppLog(LogLevel.error, 'Queue',
            'Failed service=$service; item=${after.itemId}; ${after.error ?? 'unknown'}');
      }
    }
    if (after.status == 'failed' &&
        isExtensionVerificationRequired(after.error ?? '') &&
        logged.add('verification')) {
      final service = after.verificationService ?? after.service ?? 'auto';
      printAppLog(LogLevel.warning, 'Queue',
          'Verification required for service/extension=$service; item=${after.itemId}');
    }
  }

  void _removeLocal(String itemId) {
    state = [for (final e in state) if (e.itemId != itemId) e];
    _samples.remove(itemId);
    _loggedLifecycleEvents.remove(itemId);

  }

  // --- Rate-limit (HTTP 429) backoff — ported from SpotiFLAC ---------------

  /// Gives a rate-limited item ONE delayed retry (mirrors upstream's
  /// _handleRateLimitedDownload): shows it as retrying, waits out the backoff so
  /// the shared API's limit resets, then re-queues it. Returns whether a retry
  /// was scheduled (false once the item has already used its one retry). The
  /// wait intentionally blocks the sequential queue so we stop hammering the API.
  Future<bool> _handleRateLimited(String itemId, String errorMsg) async {
    if (_rateLimitRetriedItemIds.contains(itemId)) return false;
    _rateLimitRetriedItemIds.add(itemId);
    final delay = rateLimitBackoffDelay(errorMsg);
    printAppLog(LogLevel.warning, 'Queue',
        'Rate-limit retry scheduled in ${delay.inSeconds}s; item=$itemId; $errorMsg');
    _setStatus(itemId, 'downloading',
        error: 'Rate limited · retrying after ${delay.inSeconds}s');
    await Future<void>.delayed(delay);
    if (!state.any((e) => e.itemId == itemId)) return true; // removed/cancelled
    _setStatus(itemId, 'queued', error: null);
    unawaited(_processQueue());
    return true;
  }
}

final nativeDownloadWorkerProvider =
    Provider<NativeDownloadWorker>((ref) => NativeDownloadWorker());

final downloadQueueProvider =
    NotifierProvider<DownloadQueueController, List<DownloadEntry>>(
  DownloadQueueController.new,
);

/// True when [err] is an API rate-limit (HTTP 429 / "rate limit" / "too many
/// requests"). The backend surfaces these as e.g. "All providers failed. Last
/// error: HTTP 429 for https://api.zarz.moe/...".
bool isRateLimitError(String? err) {
  if (err == null) return false;
  final l = err.toLowerCase();
  return l.contains('rate limit') ||
      l.contains('rate_limit') ||
      l.contains('too many requests') ||
      l.contains('http 429') ||
      l.contains('status 429') ||
      l.contains('429 for ') ||
      l.contains('429:') ||
      l.contains('429;');
}

/// Backoff before a rate-limit retry: honours a `Retry-After: N` in the error
/// message, else 30s, clamped to 5–300s. Mirrors upstream's
/// _rateLimitBackoffDelay.
Duration rateLimitBackoffDelay(String errorMsg) {
  final m = RegExp(
    r'retry[- ]?after(?: seconds)?[:= ]+(\d+)',
    caseSensitive: false,
  ).firstMatch(errorMsg.toLowerCase());
  final parsed = m == null ? null : int.tryParse(m.group(1) ?? '');
  final seconds = (parsed ?? 30).clamp(5, 300).toInt();
  return Duration(seconds: seconds);
}

/// Folds a backend `retry_after_seconds` value into [err] as a `retry-after: N`
/// suffix so [rateLimitBackoffDelay] honors the server's Retry-After instead of
/// the 30s default (which retries too early and gets the IP re-throttled). The
/// backend already carries this value in its result JSON, but it isn't always in
/// the error string that reaches the backoff parser. Mirrors SpotiFLAC, which
/// appends the same token before computing the backoff. No-op when [seconds] <= 0,
/// [err] is null/empty, or a retry-after token is already present.
String? foldRetryAfterSeconds(String? err, int seconds) {
  if (err == null || err.isEmpty || seconds <= 0) return err;
  if (err.toLowerCase().contains('retry-after')) return err;
  return '$err retry-after: $seconds';
}

// Only this upstream destination-collision error means the final file exists.
String? _existingLibraryPath(String? error) {
  const prefix = 'resolve album folder: open ';
  const suffix = ': file exists';
  if (error == null || !error.startsWith(prefix) || !error.endsWith(suffix)) {
    return null;
  }
  final path = error.substring(prefix.length, error.length - suffix.length);
  return path.isNotEmpty ? path : null;
}

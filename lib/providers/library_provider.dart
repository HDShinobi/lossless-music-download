import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/library_entry.dart';
import '../models/track.dart';
import '../services/history_database.dart';
import 'download_history_provider.dart';
import 'download_dir_provider.dart';
import 'extensions_provider.dart';

export '../models/library_entry.dart';

// Override in tests to provide a temp dir without calling path_provider.
final libraryCoverCacheDirProvider = Provider<Future<String>>(
  (_) async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/covers');
    await d.create(recursive: true);
    return d.path;
  },
);

final libraryProvider = FutureProvider<List<LibraryEntry>>((ref) async {
  final dir = await ref.watch(downloadDirProvider.future);
  final d = Directory(dir);
  if (!d.existsSync()) return [];

  final bridge = ref.read(backendBridgeProvider);

  // Ensure the Go backend knows where to cache extracted cover art.
  final coverDir = await ref.read(libraryCoverCacheDirProvider);
  await bridge.setLibraryCoverCacheDir(coverDir);

  // Scan the folder — Go reads embedded tags for ALL files.
  final items = await bridge.scanLibraryFolder(dir);

  final entries = items.map((item) {
    final filePath = item['filePath'] as String? ?? '';
    final filename = filePath.isNotEmpty ? filePath.split('/').last : '';
    final ext = filename.contains('.')
        ? filename.split('.').last.toUpperCase()
        : '';
    final coverPath = item['coverPath'] as String?;
    final durationSec = (item['duration'] as num?)?.toInt();

    // Read tag-derived fields from scanner.
    String? artistName = (item['artistName'] as String?)?.trim().isNotEmpty == true
        ? item['artistName'] as String
        : null;
    String? albumName = (item['albumName'] as String?)?.trim().isNotEmpty == true
        ? item['albumName'] as String
        : null;

    // Fall back to folder-path parsing when Go couldn't read embedded tags.
    // Expected layout: {downloadDir}/{artist}/{album}/{track}.ext
    bool tagsFromFallback = item['metadataFromFilename'] as bool? ?? false;
    if (artistName == null || albumName == null) {
      final relative = filePath.replaceFirst(dir, '').replaceAll(RegExp(r'^/+'), '');
      final parts = relative.split('/');
      if (parts.length >= 3) {
        artistName ??= parts[0];
        albumName ??= parts[1];
        tagsFromFallback = true;
      }
    }

    return LibraryEntry(
      path: filePath,
      name: filename,
      title: (item['trackName'] as String?)?.trim().isNotEmpty == true
          ? item['trackName'] as String
          : null,
      sizeBytes: 0,  // lengthSync removed — not rendered in UI, causes sync I/O
      artistName: artistName,
      albumName: albumName,
      coverPath: (coverPath != null && coverPath.isNotEmpty) ? coverPath : null,
      durationMs: durationSec != null ? durationSec * 1000 : null,
      format: ext,
      verified: ext == 'FLAC' || ext == 'ALAC',
      tagsFromFallback: tagsFromFallback,
      trackNumber: (item['trackNumber'] as num?)?.toInt(),
      discNumber: (item['discNumber'] as num?)?.toInt(),
      isrc: item['isrc'] as String?,
    );
  }).toList()
    ..sort((a, b) => (a.title ?? a.name).compareTo(b.title ?? b.name));
  // Reuse the scan already needed by Library. Never start a second scan just
  // for backfill. Repair at most 128 paths; seed in 256-row pages, yielding
  // between pages so the initial library can render while indexing continues.
  try {
    final history = await ref.read(historyDatabaseProvider.future);
    final repaired = await history.relocate(dir, scannedEntries: entries);
    final seeds = entries.map((e) => HistoryEntry(
      id: 'scan:${e.path}',
      track: Track(id: '', name: e.title ?? e.name, artists: e.artistName ?? '',
        albumName: e.albumName, durationMs: e.durationMs, isrc: e.isrc,
        trackNumber: e.trackNumber, discNumber: e.discNumber),
      service: 'library', filePath: e.path, downloadedAt: DateTime.fromMillisecondsSinceEpoch(0),
    )).toList();
    final seeded = entries.isEmpty ? 0 : await history.backfill(dir, seeds);
    if (ref.mounted && (repaired > 0 || seeded > 0)) {
      ref.read(historyRevisionProvider.notifier).changed();
    }
    if (entries.isNotEmpty && ref.mounted) {
      unawaited(_continueHistoryBackfill(ref, history, dir, seeds));
    }
  } catch (_) {
    // The library remains usable if history storage is temporarily unavailable.
  }
  return entries;
});

Future<void> _continueHistoryBackfill(Ref ref, HistoryDatabase history,
    String root, List<HistoryEntry> entries) async {
  try {
    while (ref.mounted && await history.hasPendingBackfill(root)) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!ref.mounted) return;
      final seeded = await history.backfill(root, entries);
      if (ref.mounted && seeded > 0) {
        ref.read(historyRevisionProvider.notifier).changed();
      }
    }
  } catch (_) {
    // Persisted cursor resumes on the next scan after a transient storage error.
  }
}

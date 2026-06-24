import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'download_dir_provider.dart';
import 'extensions_provider.dart';

// Override in tests to provide a temp dir without calling path_provider.
final libraryCoverCacheDirProvider = Provider<Future<String>>(
  (_) async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/covers');
    await d.create(recursive: true);
    return d.path;
  },
);

class LibraryEntry {
  final String path;
  final String name;
  final String? title;
  final int sizeBytes;
  final String? artistName;
  final String? albumName;
  /// Local file path to extracted cover art, or null if not available.
  final String? coverPath;
  final int? durationMs;
  final String format;
  final bool verified;
  /// True when artist/album were inferred from the folder path because the
  /// embedded audio tags could not be read (e.g. M4A missing ilst atom).
  final bool tagsFromFallback;

  const LibraryEntry({
    required this.path,
    required this.name,
    this.title,
    required this.sizeBytes,
    this.artistName,
    this.albumName,
    this.coverPath,
    this.durationMs,
    required this.format,
    required this.verified,
    this.tagsFromFallback = false,
  });
}

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

  return items.map((item) {
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
      sizeBytes: filePath.isNotEmpty
          ? (File(filePath).existsSync() ? File(filePath).lengthSync() : 0)
          : 0,
      artistName: artistName,
      albumName: albumName,
      coverPath: (coverPath != null && coverPath.isNotEmpty) ? coverPath : null,
      durationMs: durationSec != null ? durationSec * 1000 : null,
      format: ext,
      verified: ext == 'FLAC',
      tagsFromFallback: tagsFromFallback,
    );
  }).toList()
    ..sort((a, b) => (a.title ?? a.name).compareTo(b.title ?? b.name));
});

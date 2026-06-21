import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'download_dir_provider.dart';

class LibraryEntry {
  final String path;
  final String name;
  final int sizeBytes;
  final String? artistName;
  final String? albumName;
  final String format;
  final bool verified;

  const LibraryEntry({
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.artistName,
    this.albumName,
    required this.format,
    required this.verified,
  });
}

const _audioExtensions = {
  '.flac',
  '.m4a',
  '.mp3',
  '.alac',
  '.opus',
  '.ogg',
  '.wav',
  '.aiff',
};

final libraryProvider = FutureProvider<List<LibraryEntry>>((ref) async {
  final dir = await ref.watch(downloadDirProvider.future);
  final d = Directory(dir);
  if (!d.existsSync()) return [];
  final files = d
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (f) => _audioExtensions.contains('.${f.path.split('.').last.toLowerCase()}'),
      );
  final entries = files.map((f) {
    final relativePath = f.path.startsWith(dir)
        ? f.path.substring(dir.length).replaceFirst(RegExp(r'^/+'), '')
        : f.path;
    final segments = relativePath.split('/').where((s) => s.isNotEmpty).toList();

    String? artistName;
    String? albumName;
    if (segments.length >= 3) {
      artistName = segments[0];
      albumName = segments[1];
    }

    final ext = f.path.split('.').last.toUpperCase();
    final format = ext;
    final verified = format == 'FLAC';

    return LibraryEntry(
      path: f.path,
      name: f.uri.pathSegments.last,
      sizeBytes: f.lengthSync(),
      artistName: artistName,
      albumName: albumName,
      format: format,
      verified: verified,
    );
  }).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  return entries;
});

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'download_dir_provider.dart';

class LibraryEntry {
  final String path;
  final String name;
  final int sizeBytes;

  const LibraryEntry(this.path, this.name, this.sizeBytes);
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
  final entries = files
      .map((f) => LibraryEntry(f.path, f.uri.pathSegments.last, f.lengthSync()))
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  return entries;
});

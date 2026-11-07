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

  /// Position within the album, from embedded tags. Null when untagged.
  final int? trackNumber;
  final int? discNumber;
  final String? isrc;

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
    this.trackNumber,
    this.discNumber,
    this.isrc,
  });
}

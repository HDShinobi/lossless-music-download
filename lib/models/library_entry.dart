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
  final String? albumArtist, releaseDate, genre, composer, label, copyright;
  final int? totalTracks, totalDiscs;

  // Scanner placeholders are display values, never embedded tag evidence.
  // Keep them out of both history relocation and reorganization precedence.
  String? get taggedTitle {
    final filename = path.split('/').last;
    final dot = filename.lastIndexOf('.');
    final stem = dot < 0 ? filename : filename.substring(0, dot);
    return _tagText(title, stem);
  }

  String? get taggedArtistName => _tagText(artistName, 'Unknown Artist');
  String? get taggedAlbumName => _tagText(albumName, 'Unknown Album');

  String? _tagText(String? value, String placeholder) =>
      tagsFromFallback ||
          value == null ||
          value.trim().isEmpty ||
          value.trim() == placeholder
      ? null
      : value;

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
    this.albumArtist,
    this.releaseDate,
    this.genre,
    this.composer,
    this.label,
    this.copyright,
    this.totalTracks,
    this.totalDiscs,
  });
}

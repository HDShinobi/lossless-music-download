/// Download path construction.
///
/// The Go engine treats `filenameFormat` as a single **basename** — before
/// writing it runs the whole string through `sanitizeFilename`, which turns `/`
/// into a space (a filename containing `/` is illegal on every filesystem). So
/// a template like `{artist}/{album}/{title}` never produces folders; it
/// collapses into one flat name.
///
/// Following SpotiFLAC, folder layout is therefore a *separate* concern from the
/// filename template: we resolve a relative folder here, sanitizing each segment
/// on its own so the hierarchy survives, and hand the engine an absolute
/// `outputDir` plus a flat basename template.
library;

/// How downloads are grouped into folders under the download directory.
enum FolderOrganization {
  /// Everything in one folder.
  none,

  /// `<Artist>/`
  artist,

  /// `<Album>/`
  album,

  /// `<Artist>/<Album>/`
  artistAlbum;

  /// Persisted form. Matches SpotiFLAC's `folderOrganization` setting values so
  /// the two apps can read each other's settings.
  String get storageValue => switch (this) {
        FolderOrganization.none => 'none',
        FolderOrganization.artist => 'artist',
        FolderOrganization.album => 'album',
        FolderOrganization.artistAlbum => 'artist_album',
      };

  static FolderOrganization fromStorage(String? value) =>
      switch (value?.trim().toLowerCase()) {
        'none' => FolderOrganization.none,
        'artist' => FolderOrganization.artist,
        'album' => FolderOrganization.album,
        'artist_album' => FolderOrganization.artistAlbum,
        _ => FolderOrganization.artistAlbum,
      };
}

/// The subset of track metadata that folder names are built from.
class FolderMetadata {
  const FolderMetadata({
    required this.artist,
    this.albumArtist,
    this.album,
  });

  final String artist;
  final String? albumArtist;
  final String? album;
}

/// Characters no Android/Linux/Windows filesystem accepts in a path segment.
final _invalidSegmentChars = RegExp(r'[\\/:*?"<>|]');
final _whitespaceRun = RegExp(r'\s+');

/// Cleans one path segment. Unlike the engine's `sanitizeFilename` this runs per
/// segment, so `/` between segments is preserved by the caller.
String sanitizeFolderSegment(String name) {
  final withoutControl =
      name.runes.where((r) => r >= 0x20 && r != 0x7f).map(String.fromCharCode);
  var out = withoutControl
      .join()
      .replaceAll(_invalidSegmentChars, ' ')
      .replaceAll(_whitespaceRun, ' ')
      .trim();
  // Trailing dots and leading/trailing spaces break Windows shares and confuse
  // Android's media scanner; a leading dot would also hide the folder.
  out = out.replaceAll(RegExp(r'^[.\s]+'), '').replaceAll(RegExp(r'[.\s]+$'), '');
  return out.isEmpty ? 'Unknown' : out;
}

/// Strips featured artists so "A feat. B" and "A" land in the same folder.
final _featuredArtist = RegExp(
  r'\s*(?:feat\.?|ft\.?|featuring|with)\s+.*$',
  caseSensitive: false,
);

/// Builds the relative folder for [track] under the download directory.
/// Returns `''` when no folder should be created.
String buildRelativeFolder(FolderOrganization mode, FolderMetadata track) {
  if (mode == FolderOrganization.none) return '';

  // Prefer the album artist: it keeps compilations and features together in one
  // folder instead of scattering them per track credit.
  final rawArtist = [track.albumArtist, track.artist]
      .firstWhere((v) => v != null && v.trim().isNotEmpty, orElse: () => null);
  final artist = rawArtist == null
      ? null
      : sanitizeFolderSegment(rawArtist.replaceAll(_featuredArtist, ''));
  final album = (track.album?.trim().isNotEmpty ?? false)
      ? sanitizeFolderSegment(track.album!)
      : null;

  final segments = switch (mode) {
    FolderOrganization.artist => [artist],
    FolderOrganization.album => [album],
    FolderOrganization.artistAlbum => [artist, album],
    FolderOrganization.none => const <String?>[],
  };

  return segments.whereType<String>().join('/');
}

/// The flat basename template to pair with [mode].
///
/// When downloads are grouped into folders the artist and album already live in
/// the path, so the filename stays short. Without folders the filename is all
/// the user has to tell two tracks apart, so it carries the artist too.
String basenameTemplateFor(FolderOrganization mode) =>
    mode == FolderOrganization.none ? '{artist} - {title}' : '{track}. {title}';

final _placeholder = RegExp(r'\{([a-z_]+)(?::[^}]*)?\}');

/// Removes placeholders whose value is empty, together with the punctuation left
/// stranded around them — otherwise a missing track number renders `{track}.
/// {title}` as `". Title"` and a missing year renders `({year})` as `()`.
///
/// Contract: [values] carries every placeholder the caller could resolve, using
/// `''` for the ones that resolved to nothing. A placeholder *absent* from
/// [values] is one only the engine understands (padded numbers, date formats),
/// so it is left in place — pruning those would silently drop parts of a user's
/// template.
String pruneEmptyPlaceholders(String template, Map<String, String> values) {
  const gap = '\u0000';

  var out = template.replaceAllMapped(_placeholder, (m) {
    final key = m.group(1)!;
    if (!values.containsKey(key)) return m.group(0)!;
    return values[key]!.trim().isEmpty ? gap : m.group(0)!;
  });

  if (!out.contains(gap)) return template;

  // Bracketed groups that lost their only content go entirely.
  out = out.replaceAll(RegExp('[(\\[]\\s*$gap\\s*[)\\]]'), gap);
  // Then the gap plus any separator glued to one side of it.
  out = out
      .replaceAll(RegExp('\\s*[-–—.,/]?\\s*$gap\\s*[-–—.,/]?\\s*'), ' ')
      .replaceAll(_whitespaceRun, ' ')
      .trim();
  out = out.replaceAll(RegExp(r'^[-–—.,/\s]+'), '').replaceAll(RegExp(r'[-–—.,/\s]+$'), '');

  // Never hand the engine an empty template; it would fall back to a generic
  // "artist - title" and lose the user's intent entirely.
  return out.isEmpty ? template : out;
}

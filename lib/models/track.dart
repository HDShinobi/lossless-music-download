/// A search-result / downloadable track.
///
/// Fields mirror SpotiFLAC-Mobile's richer Track model (adopted for the fork)
/// so search results carry full metadata and the download request can forward
/// it. The extra fields are all optional, so existing call sites keep working.
class Track {
  final String id, name, artists;
  final String? albumName, albumArtist, coverUrl, isrc;
  final int? durationMs;

  // Rich metadata from the metadata-provider search JSON.
  final String? source; // provider/extension id that returned this result
  final int? trackNumber, discNumber, totalTracks, totalDiscs;
  final String? releaseDate, composer;
  final String? audioQuality; // e.g. "HiFi", "Lossless", "Hi-Res" (badge)
  final String? audioModes; // e.g. "DOLBY_ATMOS"

  const Track({
    required this.id,
    required this.name,
    required this.artists,
    this.albumName,
    this.albumArtist,
    this.coverUrl,
    this.isrc,
    this.durationMs,
    this.source,
    this.trackNumber,
    this.discNumber,
    this.totalTracks,
    this.totalDiscs,
    this.releaseDate,
    this.composer,
    this.audioQuality,
    this.audioModes,
  });

  factory Track.fromJson(Map<String, dynamic> j) {
    // duration may arrive as duration_ms (ms) or duration (seconds).
    final durMs = (j['duration_ms'] as num?)?.toInt() ??
        ((j['duration'] as num?) != null
            ? ((j['duration'] as num) * 1000).round()
            : null);
    return Track(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      artists:
          (j['artists'] ?? j['artist'] ?? j['artist_name'] ?? '').toString(),
      albumName: (j['album_name'] ?? j['album'])?.toString(),
      albumArtist: j['album_artist']?.toString(),
      coverUrl: (j['cover_url'] ?? j['images'] ?? j['cover'])?.toString(),
      isrc: j['isrc']?.toString(),
      durationMs: durMs,
      source: (j['source'] ?? j['extension_id'] ?? j['provider_id'])?.toString(),
      trackNumber: (j['track_number'] as num?)?.toInt(),
      discNumber: (j['disc_number'] as num?)?.toInt(),
      totalTracks: (j['total_tracks'] as num?)?.toInt(),
      totalDiscs: (j['total_discs'] as num?)?.toInt(),
      releaseDate: j['release_date']?.toString(),
      composer: j['composer']?.toString(),
      audioQuality: j['audio_quality']?.toString(),
      audioModes: j['audio_modes']?.toString(),
    );
  }

  /// Quality label for a search badge (e.g. "Hi-Res"), or null if unknown.
  String? get qualityBadge {
    final q = audioQuality?.trim();
    return (q != null && q.isNotEmpty) ? q : null;
  }

  bool get isAtmos => (audioModes ?? '').toUpperCase().contains('DOLBY_ATMOS');
}

class DownloadRequest {
  final String trackName, artistName, outputDir;
  final String? itemId, albumName, albumArtist, isrc, spotifyId, qobuzId,
      tidalId, coverUrl, releaseDate, composer, quality, source, service,
      filenameFormat;
  final int? durationMs, trackNumber, discNumber, totalTracks, totalDiscs;
  final bool useExtensions, useFallback, embedMetadata, embedMaxQualityCover,
      embedLyrics, writeLrcSidecar;

  // SpotiFLAC metadata fields for embedding into audio file tags.
  final String? genre;
  final String? label;
  final String? copyright;

  // SpotiFLAC contract fields with defaults matching SpotiFLAC's defaults.
  final String artistTagMode;
  final String lyricsMode;
  final String songLinkRegion;

  const DownloadRequest({
    required this.trackName, required this.artistName, required this.outputDir,
    this.itemId,
    this.albumName, this.albumArtist, this.isrc, this.spotifyId, this.qobuzId,
    this.tidalId, this.coverUrl, this.releaseDate, this.composer,
    this.durationMs, this.trackNumber, this.discNumber, this.totalTracks,
    this.totalDiscs, this.quality, this.source, this.service,
    this.filenameFormat = '{artist}/{album} ({year})/{track}. {title}',
    this.useExtensions = true,
    this.useFallback = true,
    this.embedMetadata = true,
    this.embedMaxQualityCover = true,
    this.embedLyrics = true,
    this.writeLrcSidecar = false,
    this.genre,
    this.label,
    this.copyright,
    this.artistTagMode = 'joined',
    this.lyricsMode = 'embed',
    this.songLinkRegion = 'US',
  });

  Map<String, dynamic> toJson() => {
        'contract_version': 1,
        'track_name': trackName,
        'artist_name': artistName,
        'output_dir': outputDir,
        if (itemId != null) 'item_id': itemId,
        if (albumName != null) 'album_name': albumName,
        if (albumArtist != null) 'album_artist': albumArtist,
        if (isrc != null) 'isrc': isrc,
        if (trackNumber != null) 'track_number': trackNumber,
        if (discNumber != null) 'disc_number': discNumber,
        if (totalTracks != null) 'total_tracks': totalTracks,
        if (totalDiscs != null) 'total_discs': totalDiscs,
        if (releaseDate != null) 'release_date': releaseDate,
        if (composer != null) 'composer': composer,
        if (spotifyId != null && spotifyId!.isNotEmpty) 'spotify_id': spotifyId,
        if (qobuzId != null && qobuzId!.isNotEmpty) 'qobuz_id': qobuzId,
        if (tidalId != null && tidalId!.isNotEmpty) 'tidal_id': tidalId,
        if (coverUrl != null && coverUrl!.isNotEmpty) 'cover_url': coverUrl,
        if (durationMs != null) 'duration_ms': durationMs,
        if (quality != null) 'quality': quality,
        if (source != null) 'source': source,
        if (service != null && service!.isNotEmpty) 'service': service,
        if (genre != null && genre!.isNotEmpty) 'genre': genre,
        if (label != null && label!.isNotEmpty) 'label': label,
        if (copyright != null && copyright!.isNotEmpty) 'copyright': copyright,
        'filename_format': filenameFormat,
        'use_extensions': useExtensions,
        'use_fallback': useFallback,
        'embed_metadata': embedMetadata,
        'embed_max_quality_cover': embedMaxQualityCover,
        'embed_lyrics': embedLyrics,
        'write_lrc_sidecar': writeLrcSidecar,
        'artist_tag_mode': artistTagMode,
        'lyrics_mode': lyricsMode,
        'songlink_region': songLinkRegion,
      };
}

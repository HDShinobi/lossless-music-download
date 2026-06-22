class DownloadRequest {
  final String trackName, artistName, outputDir;
  final String? itemId, albumName, isrc, spotifyId, qobuzId, tidalId, coverUrl,
      quality, source, filenameFormat;
  final int? durationMs;
  final bool useExtensions, embedMetadata, embedMaxQualityCover, embedLyrics;
  const DownloadRequest({
    required this.trackName, required this.artistName, required this.outputDir,
    this.itemId,
    this.albumName, this.isrc, this.spotifyId, this.qobuzId, this.tidalId,
    this.coverUrl, this.durationMs, this.quality, this.source,
    this.filenameFormat = '{artist}/{album}/{track} {title}',
    this.useExtensions = true, this.embedMetadata = true,
    this.embedMaxQualityCover = true, this.embedLyrics = true,
  });
  Map<String, dynamic> toJson() => {
        'track_name': trackName,
        'artist_name': artistName,
        'output_dir': outputDir,
        if (itemId != null) 'item_id': itemId,
        if (albumName != null) 'album_name': albumName,
        if (isrc != null) 'isrc': isrc,
        // Track identifiers — the backend resolves the exact track from these
        // (spotify_id, else qobuz_id/tidal_id). Without one, extensions cannot
        // locate the track to download.
        if (spotifyId != null && spotifyId!.isNotEmpty) 'spotify_id': spotifyId,
        if (qobuzId != null && qobuzId!.isNotEmpty) 'qobuz_id': qobuzId,
        if (tidalId != null && tidalId!.isNotEmpty) 'tidal_id': tidalId,
        if (coverUrl != null && coverUrl!.isNotEmpty) 'cover_url': coverUrl,
        if (durationMs != null) 'duration_ms': durationMs,
        if (quality != null) 'quality': quality,
        if (source != null) 'source': source,
        'filename_format': filenameFormat,
        'use_extensions': useExtensions,
        'embed_metadata': embedMetadata,
        'embed_max_quality_cover': embedMaxQualityCover,
        'embed_lyrics': embedLyrics,
      };
}

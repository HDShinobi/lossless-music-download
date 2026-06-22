class DownloadRequest {
  final String trackName, artistName, outputDir;
  final String? itemId, albumName, isrc, spotifyId, quality, source, filenameFormat;
  final bool useExtensions, embedMetadata, embedMaxQualityCover, embedLyrics;
  const DownloadRequest({
    required this.trackName, required this.artistName, required this.outputDir,
    this.itemId,
    this.albumName, this.isrc, this.spotifyId, this.quality, this.source,
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
        if (spotifyId != null) 'spotify_id': spotifyId,
        if (quality != null) 'quality': quality,
        if (source != null) 'source': source,
        'filename_format': filenameFormat,
        'use_extensions': useExtensions,
        'embed_metadata': embedMetadata,
        'embed_max_quality_cover': embedMaxQualityCover,
        'embed_lyrics': embedLyrics,
      };
}

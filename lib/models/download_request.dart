class DownloadRequest {
  final String trackName, artistName, outputDir;
  final String? albumName, isrc, spotifyId, quality, filenameFormat;
  final bool useExtensions, embedMetadata, embedMaxQualityCover, embedLyrics;
  const DownloadRequest({
    required this.trackName, required this.artistName, required this.outputDir,
    this.albumName, this.isrc, this.spotifyId, this.quality,
    this.filenameFormat = '{artist}/{album}/{track} {title}',
    this.useExtensions = true, this.embedMetadata = true,
    this.embedMaxQualityCover = true, this.embedLyrics = true,
  });
  Map<String, dynamic> toJson() => {
        'track_name': trackName,
        'artist_name': artistName,
        'output_dir': outputDir,
        if (albumName != null) 'album_name': albumName,
        if (isrc != null) 'isrc': isrc,
        if (spotifyId != null) 'spotify_id': spotifyId,
        if (quality != null) 'quality': quality,
        'filename_format': filenameFormat,
        'use_extensions': useExtensions,
        'embed_metadata': embedMetadata,
        'embed_max_quality_cover': embedMaxQualityCover,
        'embed_lyrics': embedLyrics,
      };
}

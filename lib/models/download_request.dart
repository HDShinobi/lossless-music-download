class DownloadRequest {
  final String title, artist, outputDir;
  final String? album, isrc, spotifyId, quality, audioFormat, filenameFormat;
  final bool useExtensions, embedMetadata, embedCover, embedLyrics;
  const DownloadRequest({
    required this.title, required this.artist, required this.outputDir,
    this.album, this.isrc, this.spotifyId, this.quality, this.audioFormat,
    this.filenameFormat = '{artist}/{album}/{track} {title}',
    this.useExtensions = true, this.embedMetadata = true, this.embedCover = true, this.embedLyrics = true,
  });
  Map<String, dynamic> toJson() => {
        'title': title, 'artist': artist, 'outputDir': outputDir,
        if (album != null) 'album': album,
        if (isrc != null) 'isrc': isrc,
        if (spotifyId != null) 'spotifyId': spotifyId,
        if (quality != null) 'quality': quality,
        if (audioFormat != null) 'audioFormat': audioFormat,
        'filenameFormat': filenameFormat,
        'useExtensions': useExtensions,
        'embedMetadata': embedMetadata, 'embedCover': embedCover, 'embedLyrics': embedLyrics,
      };
}

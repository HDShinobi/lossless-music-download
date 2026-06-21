class Track {
  final String id, name, artists;
  final String? albumName, coverUrl, isrc;
  final int? durationMs;
  const Track({required this.id, required this.name, required this.artists, this.albumName, this.coverUrl, this.isrc, this.durationMs});
  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        artists: (j['artists'] ?? j['artist'] ?? '').toString(),
        albumName: j['album_name']?.toString(),
        coverUrl: j['cover_url']?.toString(),
        isrc: j['isrc']?.toString(),
        durationMs: (j['duration_ms'] as num?)?.toInt(),
      );
}

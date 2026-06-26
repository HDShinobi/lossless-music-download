import 'track.dart';

String _str(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString();
  }
  return '';
}

/// `provider:id` route id used by ArtistScreen/AlbumScreen, or a bare id when
/// the result names no provider.
String _routeId(String id, String providerId) =>
    providerId.isEmpty ? id : '$providerId:$id';

/// An artist result from a provider's custom (entity) search.
class SearchArtist {
  const SearchArtist({
    required this.id,
    required this.name,
    required this.routeId,
    this.imageUrl,
  });

  final String id;
  final String name;
  final String routeId;
  final String? imageUrl;

  factory SearchArtist.fromCustomSearch(Map<String, dynamic> m) {
    final id = _str(m, ['id']);
    final img = _str(m, ['images', 'cover_url']);
    return SearchArtist(
      id: id,
      name: _str(m, ['name', 'artists']),
      imageUrl: img.isEmpty ? null : img,
      routeId: _routeId(id, _str(m, ['provider_id', 'source'])),
    );
  }
}

/// An album result from a provider's custom (entity) search.
class SearchAlbum {
  const SearchAlbum({
    required this.id,
    required this.name,
    required this.artists,
    required this.routeId,
    this.imageUrl,
    this.releaseDate,
  });

  final String id;
  final String name;
  final String artists;
  final String routeId;
  final String? imageUrl;
  final String? releaseDate;

  String get year =>
      (releaseDate != null && releaseDate!.length >= 4)
          ? releaseDate!.substring(0, 4)
          : '';

  factory SearchAlbum.fromCustomSearch(Map<String, dynamic> m) {
    final id = _str(m, ['id']);
    final img = _str(m, ['images', 'cover_url']);
    final date = _str(m, ['release_date']);
    return SearchAlbum(
      id: id,
      name: _str(m, ['name', 'album_name']),
      artists: _str(m, ['artists', 'album_artist']),
      imageUrl: img.isEmpty ? null : img,
      releaseDate: date.isEmpty ? null : date,
      routeId: _routeId(id, _str(m, ['provider_id', 'source'])),
    );
  }
}

List<SearchArtist> parseArtists(List<Map<String, dynamic>> raw) {
  final seen = <String>{};
  final out = <SearchArtist>[];
  for (final m in raw) {
    final a = SearchArtist.fromCustomSearch(m);
    if (a.id.isEmpty || !seen.add(a.routeId)) continue;
    out.add(a);
  }
  return out;
}

List<SearchAlbum> parseAlbums(List<Map<String, dynamic>> raw) {
  final seen = <String>{};
  final out = <SearchAlbum>[];
  for (final m in raw) {
    final a = SearchAlbum.fromCustomSearch(m);
    if (a.id.isEmpty || !seen.add(a.routeId)) continue;
    out.add(a);
  }
  return out;
}

/// Combined search results: tracks (from the metadata search) plus artist and
/// album entities (from provider custom search).
class SearchResults {
  const SearchResults({
    this.tracks = const [],
    this.artists = const [],
    this.albums = const [],
  });

  final List<Track> tracks;
  final List<SearchArtist> artists;
  final List<SearchAlbum> albums;

  bool get isEmpty => tracks.isEmpty && artists.isEmpty && albums.isEmpty;

  static const empty = SearchResults();
}

/// Which result types the search filter shows.
enum SearchFilter { all, song, artist, album }

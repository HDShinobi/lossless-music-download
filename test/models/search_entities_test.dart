import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/search_entities.dart';

void main() {
  group('SearchArtist.fromCustomSearch', () {
    test('parses id/name/image/provider and builds the route id', () {
      final a = SearchArtist.fromCustomSearch({
        'id': '123',
        'name': 'Taylor Swift',
        'images': 'http://img/ts.jpg',
        'provider_id': 'deezer',
      });
      expect(a.id, '123');
      expect(a.name, 'Taylor Swift');
      expect(a.imageUrl, 'http://img/ts.jpg');
      expect(a.routeId, 'deezer:123'); // provider-prefixed for ArtistScreen
    });

    test('falls back to cover_url and bare route id without provider', () {
      final a = SearchArtist.fromCustomSearch({
        'id': '9',
        'name': 'X',
        'cover_url': 'http://img/x.jpg',
      });
      expect(a.imageUrl, 'http://img/x.jpg');
      expect(a.routeId, '9');
    });
  });

  group('SearchAlbum.fromCustomSearch', () {
    test('parses album fields incl. artist + year', () {
      final al = SearchAlbum.fromCustomSearch({
        'id': 'a1',
        'name': 'The Life of a Showgirl',
        'artists': 'Taylor Swift',
        'images': 'http://img/al.jpg',
        'release_date': '2025-10-03',
        'provider_id': 'qobuz',
      });
      expect(al.name, 'The Life of a Showgirl');
      expect(al.artists, 'Taylor Swift');
      expect(al.year, '2025');
      expect(al.routeId, 'qobuz:a1');
    });

    test('year is empty when release date is missing/short', () {
      final al = SearchAlbum.fromCustomSearch({'id': 'a', 'name': 'N'});
      expect(al.year, '');
    });
  });

  group('parseSearchEntities', () {
    test('maps a list of custom-search results, skipping empty ids', () {
      final artists = parseArtists([
        {'id': '1', 'name': 'A'},
        {'id': '', 'name': 'skip'},
        {'id': '2', 'name': 'B'},
      ]);
      expect(artists.map((a) => a.id), ['1', '2']);
    });

    test('dedups by routeId', () {
      final albums = parseAlbums([
        {'id': '1', 'name': 'A', 'provider_id': 'deezer'},
        {'id': '1', 'name': 'A dup', 'provider_id': 'deezer'},
      ]);
      expect(albums, hasLength(1));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/screens/artist_screen.dart';

ArtistAlbumCard _album({String id = 'ab12', String? providerId}) =>
    ArtistAlbumCard(
      id: id,
      name: 'Some Album',
      artists: 'Some Artist',
      providerId: providerId,
    );

void main() {
  group('albumRouteId', () {
    test('uses the album\'s own provider_id when present', () {
      expect(
        albumRouteId(_album(id: '123', providerId: 'deezer'),
            'spotify-web:artist9'),
        'deezer:123',
      );
    });

    test('falls back to the artist provider when the album omits provider_id',
        () {
      // Regression: artist albums from a non-Spotify provider used to open with
      // a bare id and got misrouted to Spotify's handleUrl -> no tracks.
      expect(
        albumRouteId(_album(id: 'ab12', providerId: null), 'deezer:artist9'),
        'deezer:ab12',
      );
    });

    test('leaves a bare id when neither album nor artist has a provider', () {
      expect(albumRouteId(_album(id: 'ab12'), 'artist9'), 'ab12');
    });
  });
}

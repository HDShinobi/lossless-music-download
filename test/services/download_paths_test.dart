import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/services/download_paths.dart';

void main() {
  group('sanitizeFolderSegment', () {
    test('replaces characters that are illegal in a path segment', () {
      expect(sanitizeFolderSegment('AC/DC'), 'AC DC');
      expect(sanitizeFolderSegment('Sigur Rós: ( )'), 'Sigur Rós ( )');
      expect(sanitizeFolderSegment(r'a\b*c?d"e<f>g|h'), 'a b c d e f g h');
    });

    test('strips control characters and collapses whitespace', () {
      expect(sanitizeFolderSegment('Ta\u0000ylor   Swift'), 'Taylor Swift');
    });

    test('trims leading/trailing dots and spaces that break filesystems', () {
      expect(sanitizeFolderSegment('  .hidden.  '), 'hidden');
    });

    test('falls back to Unknown for names with nothing usable left', () {
      expect(sanitizeFolderSegment('   '), 'Unknown');
      expect(sanitizeFolderSegment('...'), 'Unknown');
      expect(sanitizeFolderSegment(''), 'Unknown');
    });
  });

  group('buildRelativeFolder', () {
    const track = FolderMetadata(
      artist: 'Taylor Swift',
      albumArtist: 'Taylor Swift',
      album: 'The Life of a Showgirl',
    );

    test('none yields no folder at all', () {
      expect(buildRelativeFolder(FolderOrganization.none, track), '');
    });

    test('artist yields a single level', () {
      expect(
        buildRelativeFolder(FolderOrganization.artist, track),
        'Taylor Swift',
      );
    });

    test('album yields a single level', () {
      expect(
        buildRelativeFolder(FolderOrganization.album, track),
        'The Life of a Showgirl',
      );
    });

    test('artistAlbum yields two levels', () {
      expect(
        buildRelativeFolder(FolderOrganization.artistAlbum, track),
        'Taylor Swift/The Life of a Showgirl',
      );
    });

    test('prefers the album artist so compilations group together', () {
      const compilation = FolderMetadata(
        artist: 'Various Artists',
        albumArtist: 'Hans Zimmer',
        album: 'Dune',
      );
      expect(
        buildRelativeFolder(FolderOrganization.artistAlbum, compilation),
        'Hans Zimmer/Dune',
      );
    });

    test('falls back to the track artist when no album artist is present', () {
      const noAlbumArtist = FolderMetadata(
        artist: 'Taylor Swift',
        album: 'Opalite',
      );
      expect(
        buildRelativeFolder(FolderOrganization.artist, noAlbumArtist),
        'Taylor Swift',
      );
    });

    test('drops featured artists so folders do not fragment', () {
      const featured = FolderMetadata(
        artist: 'Post Malone feat. Taylor Swift',
        album: 'Fortnight',
      );
      expect(
        buildRelativeFolder(FolderOrganization.artist, featured),
        'Post Malone',
      );
    });

    test('sanitizes each segment separately, keeping the hierarchy', () {
      const slashes = FolderMetadata(artist: 'AC/DC', album: 'Back/Black');
      expect(
        buildRelativeFolder(FolderOrganization.artistAlbum, slashes),
        'AC DC/Back Black',
      );
    });

    test('omits an empty album level rather than emitting a bare slash', () {
      const noAlbum = FolderMetadata(artist: 'Taylor Swift', album: '');
      expect(
        buildRelativeFolder(FolderOrganization.artistAlbum, noAlbum),
        'Taylor Swift',
      );
    });
  });

  group('basenameTemplateFor', () {
    test('carries the artist when there are no folders to hold it', () {
      expect(
        basenameTemplateFor(FolderOrganization.none),
        '{artist} - {title}',
      );
    });

    test('stays short when folders already encode artist/album', () {
      for (final mode in [
        FolderOrganization.artist,
        FolderOrganization.album,
        FolderOrganization.artistAlbum,
      ]) {
        expect(basenameTemplateFor(mode), '{track}. {title}', reason: '$mode');
      }
    });

    test('never contains a path separator — the engine would flatten it', () {
      for (final mode in FolderOrganization.values) {
        expect(basenameTemplateFor(mode), isNot(contains('/')), reason: '$mode');
      }
    });
  });

  // Contract: the caller passes every placeholder it can resolve, using '' for
  // the ones it resolved to nothing. A placeholder absent from the map is one
  // only the engine understands, so it is left for the engine.
  group('pruneEmptyPlaceholders', () {
    test('drops an empty leading placeholder and its separator', () {
      // The observed bug: no track number left "{track}. {title}" as ". Title".
      expect(
        pruneEmptyPlaceholders(
          '{track}. {title}',
          const {'track': '', 'title': 'Opalite'},
        ),
        '{title}',
      );
    });

    test('drops empty parenthesised placeholders', () {
      // The observed bug: no release year left "{album} ({year})" as "Album ()".
      expect(
        pruneEmptyPlaceholders(
          '{album} ({year})',
          const {'album': 'The Life of a Showgirl', 'year': ''},
        ),
        '{album}',
      );
    });

    test('drops an empty trailing placeholder and its separator', () {
      expect(
        pruneEmptyPlaceholders(
          '{title} - {artist}',
          const {'title': 'Opalite', 'artist': ''},
        ),
        '{title}',
      );
    });

    test('drops several empty placeholders at once', () {
      expect(
        pruneEmptyPlaceholders(
          '{track}. {title} ({year})',
          const {'track': '', 'title': 'Opalite', 'year': ''},
        ),
        '{title}',
      );
    });

    test('keeps the template untouched when every value is present', () {
      const values = {'track': '01', 'title': 'Opalite', 'year': '2026'};
      expect(
        pruneEmptyPlaceholders('{track}. {title} ({year})', values),
        '{track}. {title} ({year})',
      );
    });

    test('leaves engine-only placeholders alone', () {
      expect(
        pruneEmptyPlaceholders('{title} [{isrc}]', const {'title': 'Opalite'}),
        '{title} [{isrc}]',
      );
    });

    test('never returns an empty template, even if nothing resolved', () {
      expect(
        pruneEmptyPlaceholders(
          '{track}. {title}',
          const {'track': '', 'title': ''},
        ),
        '{track}. {title}',
      );
    });
  });
}

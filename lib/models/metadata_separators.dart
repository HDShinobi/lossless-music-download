/// Empty separators preserve the provider's existing tag values (upstream
/// default). Only comma/semicolon-delimited metadata lists are reformatted.
class MetadataSeparators {
  static const fields = ['artist', 'album_artist', 'composer', 'genre'];
  const MetadataSeparators({
    this.artist = '',
    this.albumArtist = '',
    this.composer = '',
    this.genre = '',
  });

  final String artist, albumArtist, composer, genre;

  static bool isValid(String value) =>
      value.length <= 16 && !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);

  factory MetadataSeparators.fromJson(Map<String, dynamic> json) {
    String read(String key) {
      final value = json[key];
      return value is String && isValid(value) ? value : '';
    }

    return MetadataSeparators(
      artist: read('artist'),
      albumArtist: read('album_artist'),
      composer: read('composer'),
      genre: read('genre'),
    );
  }

  Map<String, String> toJson() => {
    'artist': artist,
    'album_artist': albumArtist,
    'composer': composer,
    'genre': genre,
  };
  bool get isDefault => toJson().values.every((v) => v.isEmpty);
  MetadataSeparators withField(String field, String value) =>
      MetadataSeparators.fromJson({...toJson(), field: value});
}

const artistTagModes = ['joined', 'split_vorbis', 'primary'];

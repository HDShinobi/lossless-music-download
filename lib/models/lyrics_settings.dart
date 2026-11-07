import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Mirrors the vendored engine's lyrics/config.rs. Empty JSON keeps its defaults.
class LyricsSettings {
  const LyricsSettings({this.providers = const [], this.options = const {}});

  static const providerNames = {
    'lrclib': 'LRCLIB',
    'netease': 'NetEase',
    'musixmatch': 'Musixmatch',
    'apple_music': 'Apple Music',
    'mornye_lyrics': 'Zarz-LRC',
    'qqmusic': 'QQ Music',
    'spotify': 'Spotify',
    'deezer': 'Deezer',
    'youtube': 'YouTube',
    'kugou': 'Kugou',
    'genius': 'Genius',
    'lyricsplus': 'LyricsPlus',
    'lrcred': 'lrc.red',
    'betterlyrics': 'BetterLyrics',
  };
  static const defaultProviders = [
    'apple_music',
    'lrcred',
    'mornye_lyrics',
    'lyricsplus',
    'lrclib',
  ];
  static const defaultOptions = <String, Object>{
    'include_translation_netease': false,
    'include_romanization_netease': false,
    'multi_person_word_by_word': true,
    'apple_elrc_word_sync': false,
    'musixmatch_language': '',
  };
  static const providersKey = 'lyrics_providers';
  static const optionsKey = 'lyrics_fetch_options';

  final List<String> providers;
  final Map<String, Object> options;
  List<String> get effectiveProviders =>
      providers.isEmpty ? defaultProviders : providers;
  String get providersJson => jsonEncode(providers);
  String get optionsJson => jsonEncode(options);

  static Future<LyricsSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> providers = const [];
    Map<String, Object> options = const {};
    try {
      final ids = jsonDecode(prefs.getString(providersKey) ?? '[]') as List;
      providers = ids
          .whereType<String>()
          .where(
            (id) =>
                providerNames.containsKey(id) ||
                (id.startsWith('extension:') && id.length > 10),
          )
          .toSet()
          .toList();
    } catch (_) {
      /* Invalid saved values fall back to engine defaults. */
    }
    try {
      final raw = jsonDecode(prefs.getString(optionsKey) ?? '{}') as Map;
      options = {
        for (final entry in defaultOptions.entries)
          if (raw[entry.key].runtimeType == entry.value.runtimeType)
            entry.key: raw[entry.key] as Object,
      };
    } catch (_) {
      /* Keep engine defaults. */
    }
    return LyricsSettings(providers: providers, options: options);
  }
}

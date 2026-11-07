import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lyrics_settings.dart';
import 'extensions_provider.dart';

final lyricsSettingsProvider =
    AsyncNotifierProvider<LyricsSettingsController, LyricsSettings>(
      LyricsSettingsController.new,
    );

class LyricsSettingsController extends AsyncNotifier<LyricsSettings> {
  @override
  Future<LyricsSettings> build() => LyricsSettings.load();

  Future<void> setProviders(List<String> providers) async {
    final current = await future;
    final next = LyricsSettings(
      providers: List.unmodifiable(providers),
      options: current.options,
    );
    await ref.read(backendBridgeProvider).setLyricsProviders(next.providers);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LyricsSettings.providersKey, next.providersJson);
    state = AsyncData(next);
  }

  Future<void> setOption(String key, Object value) async {
    final current = await future;
    if (!LyricsSettings.defaultOptions.containsKey(key)) return;
    if (key == 'musixmatch_language') {
      value = (value as String).trim().toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9_-]'),
        '',
      );
      if (value.length > 16) value = value.substring(0, 16);
    }
    final next = LyricsSettings(
      providers: current.providers,
      options: Map.unmodifiable({...current.options, key: value}),
    );
    await ref.read(backendBridgeProvider).setLyricsFetchOptions(next.options);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LyricsSettings.optionsKey, next.optionsJson);
    state = AsyncData(next);
  }
}

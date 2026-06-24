import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AskBeforeDownloadNotifier extends Notifier<bool> {
  static const _key = 'ask_before_download';

  // Tracks whether set() has been explicitly called, so the startup microtask
  // doesn't clobber a value that was already written in this session.
  bool _explicitlySet = false;

  @override
  bool build() {
    _explicitlySet = false;
    // Load persisted value on first build without blocking the UI.
    Future.microtask(() async {
      final p = await SharedPreferences.getInstance();
      if (ref.mounted && !_explicitlySet) state = p.getBool(_key) ?? false;
    });
    return false;
  }

  /// Deprecated: `build()` now auto-loads the persisted value via a microtask
  /// on first initialization. Call [set] to update the value; there is no need
  /// to call [load] manually.
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    state = p.getBool(_key) ?? false;
  }

  Future<void> set(bool value) async {
    _explicitlySet = true;
    state = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, value);
  }
}

final askBeforeDownloadProvider =
    NotifierProvider<AskBeforeDownloadNotifier, bool>(
  AskBeforeDownloadNotifier.new,
);

// ---------------------------------------------------------------------------
// Generic bool preference notifier — reusable for any on/off setting.
// ---------------------------------------------------------------------------

class _BoolPrefNotifier extends Notifier<bool> {
  _BoolPrefNotifier(this._key, this._defaultValue);

  final String _key;
  final bool _defaultValue;
  bool _explicitlySet = false;

  @override
  bool build() {
    _explicitlySet = false;
    Future.microtask(() async {
      final p = await SharedPreferences.getInstance();
      if (ref.mounted && !_explicitlySet) state = p.getBool(_key) ?? _defaultValue;
    });
    return _defaultValue;
  }

  Future<void> set(bool value) async {
    _explicitlySet = true;
    state = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, value);
  }
}

final embedMetadataProvider = NotifierProvider<_BoolPrefNotifier, bool>(
  () => _BoolPrefNotifier('embed_metadata', true),
);

final embedCoverProvider = NotifierProvider<_BoolPrefNotifier, bool>(
  () => _BoolPrefNotifier('embed_cover', true),
);

final embedLyricsProvider = NotifierProvider<_BoolPrefNotifier, bool>(
  () => _BoolPrefNotifier('embed_lyrics', true),
);

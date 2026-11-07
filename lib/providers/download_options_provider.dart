import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/download_paths.dart';
import '../services/download_templates.dart';
import '../models/metadata_separators.dart';

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
      if (ref.mounted && !_explicitlySet) state = p.getBool(_key) ?? true;
    });
    return true;
  }

  /// Deprecated: `build()` now auto-loads the persisted value via a microtask
  /// on first initialization. Call [set] to update the value; there is no need
  /// to call [load] manually.
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    state = p.getBool(_key) ?? true;
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

final autoFallbackProvider = NotifierProvider<_BoolPrefNotifier, bool>(
  () => _BoolPrefNotifier('auto_fallback', true),
);

final writeLrcSidecarProvider = NotifierProvider<_BoolPrefNotifier, bool>(
  () => _BoolPrefNotifier('write_lrc_sidecar', false),
);

// ---------------------------------------------------------------------------
// Folder organization — how downloads are grouped under the download directory.
// ---------------------------------------------------------------------------

class FolderOrganizationNotifier extends Notifier<FolderOrganization> {
  static const _key = 'folder_organization';

  bool _explicitlySet = false;

  @override
  FolderOrganization build() {
    _explicitlySet = false;
    Future.microtask(() async {
      final p = await SharedPreferences.getInstance();
      if (ref.mounted && !_explicitlySet) {
        state = FolderOrganization.fromStorage(p.getString(_key));
      }
    });
    // Default to artist/album: it is the layout library_provider's tag-less
    // fallback parses paths for, so grouping keeps the library usable even when
    // a download arrives without embedded tags.
    return FolderOrganization.artistAlbum;
  }

  Future<void> set(FolderOrganization value) async {
    _explicitlySet = true;
    state = value;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, value.storageValue);
  }
}

final folderOrganizationProvider =
    NotifierProvider<FolderOrganizationNotifier, FolderOrganization>(
  FolderOrganizationNotifier.new,
);

// Empty templates opt into the legacy, folder-dependent defaults.
class _StringPrefNotifier extends Notifier<String> {
  _StringPrefNotifier(this.key, this.defaultValue, this.valid);
  final String key, defaultValue;
  final bool Function(String) valid;
  bool _explicitlySet = false;

  @override
  String build() {
    _explicitlySet = false;
    Future.microtask(() async {
      final p = await SharedPreferences.getInstance();
      final value = p.getString(key) ?? defaultValue;
      if (ref.mounted && !_explicitlySet) {
        state = valid(value) ? value : defaultValue;
      }
    });
    return defaultValue;
  }

  Future<void> set(String value) async {
    if (!valid(value)) return;
    _explicitlySet = true;
    state = value;
    final p = await SharedPreferences.getInstance();
    await p.setString(key, value);
  }
}

final filenameTemplateProvider = NotifierProvider<_StringPrefNotifier, String>(
  () => _StringPrefNotifier('filename_template', '',
    (v) => v.isEmpty || DownloadTemplates.validate(v) == null));
final albumFolderTemplateProvider = NotifierProvider<_StringPrefNotifier, String>(
  () => _StringPrefNotifier('album_folder_template', '',
    (v) => v.isEmpty || DownloadTemplates.validate(v, folder: true) == null));
final artistTagModeProvider = NotifierProvider<_StringPrefNotifier, String>(
  () => _StringPrefNotifier('artist_tag_mode', 'joined', artistTagModes.contains));

class MetadataSeparatorsNotifier extends Notifier<MetadataSeparators> {
  static const _key = 'metadata_separators';
  bool _explicitlySet = false;

  @override
  MetadataSeparators build() {
    _explicitlySet = false;
    Future.microtask(() async {
      final p = await SharedPreferences.getInstance();
      try {
        final json = jsonDecode(p.getString(_key) ?? '{}');
        if (ref.mounted && !_explicitlySet && json is Map<String, dynamic>) {
          state = MetadataSeparators.fromJson(json);
        }
      } on FormatException {
        // A damaged preference must not prevent downloads or opening settings.
      }
    });
    return const MetadataSeparators();
  }

  Future<void> setField(String field, String value) async {
    if (!MetadataSeparators.fields.contains(field) ||
        !MetadataSeparators.isValid(value)) {
      return;
    }
    _explicitlySet = true;
    state = state.withField(field, value);
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(state.toJson()));
  }
}

final metadataSeparatorsProvider =
    NotifierProvider<MetadataSeparatorsNotifier, MetadataSeparators>(
      MetadataSeparatorsNotifier.new);

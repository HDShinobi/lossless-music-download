import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/track.dart';
import '../models/installed_extension.dart';
import '../models/download_request.dart';
import '../models/download_progress.dart';
import '../models/audio_quality.dart';
import '../models/server_status.dart';

class BackendBridge {
  BackendBridge([MethodChannel? channel])
      : _c = channel ?? const MethodChannel('xyz.losslessmusic/native');
  final MethodChannel _c;

  static const _progressChannel = EventChannel('xyz.losslessmusic/progress');

  Future<void> initExtensionSystem(String extDir, String dataDir) =>
      _c.invokeMethod('initExtensionSystem', {'extDir': extDir, 'dataDir': dataDir});

  Future<String?> installExtension(String path) =>
      _c.invokeMethod<String>('loadExtensionFromPath', {'path': path});

  /// Loads every persisted extension under [dirPath] into the runtime. Must be
  /// called after [initExtensionSystem] on startup, otherwise extensions
  /// installed in a previous session stay on disk but are absent from
  /// [getInstalledExtensions]. Returns the backend JSON summary (ignored here).
  Future<String?> loadExtensionsFromDir(String dirPath) =>
      _c.invokeMethod<String>('loadExtensionsFromDir', {'dirPath': dirPath});

  Future<List<InstalledExtension>> getInstalledExtensions() async {
    final raw = await _c.invokeMethod<String>('getInstalledExtensions');
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    final list = decoded is List ? decoded : (decoded['extensions'] as List? ?? []);
    return list.map((e) => InstalledExtension.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> setExtensionEnabled(String id, bool enabled) =>
      _c.invokeMethod('setExtensionEnabled', {'id': id, 'enabled': enabled});

  Future<void> removeExtension(String id) => _c.invokeMethod('removeExtension', {'id': id});

  Future<List<Track>> searchTracks(
    String query, {
    int limit = 20,
    bool includeExtensions = true,
  }) async {
    final raw = await _c.invokeMethod<String>(
      'searchTracks',
      {'query': query, 'limit': limit, 'includeExtensions': includeExtensions},
    );
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    final list = decoded is List ? decoded : (decoded['tracks'] as List? ?? []);
    return list.map((e) => Track.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<Map<String, dynamic>> downloadByStrategy(DownloadRequest req) async {
    final raw = await _c.invokeMethod<String>(
      'downloadByStrategy',
      {'requestJson': jsonEncode(req.toJson())},
    );
    return raw == null || raw.isEmpty ? {} : Map<String, dynamic>.from(jsonDecode(raw));
  }

  Future<List<DownloadProgress>> getAllProgress() async {
    final raw = await _c.invokeMethod<String>('getAllProgress');
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    final List<dynamic> list = decoded is List
        ? decoded
        : ((decoded['items'] as Map?)?.values.toList() ?? []);
    return list.map((e) => DownloadProgress.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  /// Real-time progress stream — uses EventChannel on Android (pushed by
  /// native at ~300 ms intervals), falls back to 1-second polling elsewhere.
  Stream<List<DownloadProgress>> progressStream() {
    if (Platform.isAndroid) {
      return _progressChannel.receiveBroadcastStream().map((event) {
        final raw = event as String? ?? '';
        if (raw.isEmpty) return const <DownloadProgress>[];
        final decoded = jsonDecode(raw);
        final list = decoded is List
            ? decoded
            : ((decoded['items'] as Map?)?.values.toList() ?? []);
        return list
            .map((e) => DownloadProgress.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
      }).handleError((Object e, StackTrace st) {
        // Log deserialization errors; do NOT close the stream.
        debugPrint('[progressStream] error: $e');
      });
    }
    // Non-Android fallback: poll getAllProgress every second.
    return Stream.periodic(const Duration(seconds: 1)).asyncMap(
      (_) => getAllProgress().catchError((_) => const <DownloadProgress>[]),
    );
  }

  Future<void> cancelDownload(String itemId) =>
      _c.invokeMethod('cancelDownload', {'itemId': itemId});

  /// Probes a local audio file's measured quality (bit depth, sample rate,
  /// bitrate, codec). Returns null if the path cannot be probed.
  Future<AudioQuality?> getAudioQuality(String path) async {
    final raw = await _c.invokeMethod<String>('getAudioQuality', {'path': path});
    if (raw == null || raw.isEmpty) return null;
    return AudioQuality.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
  }

  /// Resolves a shared/deep-link URL (Spotify, Deezer, ...) via the installed
  /// extensions. Returns the decoded result map ({type, track|tracks, ...}) or
  /// null if nothing handled it.
  Future<Map<String, dynamic>?> handleUrl(String url) async {
    final raw = await _c.invokeMethod<String>('handleUrl', {'url': url});
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  /// Fetches metadata for [resourceType] ("artist", "album", "track") with
  /// [resourceId] (provider-native, no prefix) from [providerId] extension.
  /// Returns the decoded map or null on error/empty.
  Future<Map<String, dynamic>?> getProviderMetadata(
    String providerId,
    String resourceType,
    String resourceId,
  ) async {
    final raw = await _c.invokeMethod<String>('getProviderMetadata', {
      'providerId': providerId,
      'resourceType': resourceType,
      'resourceId': resourceId,
    });
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  /// Fetches lyrics as LRC text. With [filePath] empty, fetches online from the
  /// configured lyrics providers; otherwise reads embedded lyrics from the file.
  /// Returns empty string when no lyrics are found.
  Future<String> getLyricsLRC({
    String spotifyId = '',
    required String trackName,
    required String artistName,
    String filePath = '',
    int durationMs = 0,
  }) async {
    final raw = await _c.invokeMethod<String>('getLyricsLRC', {
      'spotifyId': spotifyId,
      'trackName': trackName,
      'artistName': artistName,
      'filePath': filePath,
      'durationMs': durationMs,
    });
    return raw ?? '';
  }

  /// Writes [metadata] (lowercase tag keys: title, artist, album, album_artist,
  /// date, genre, track_number, lyrics, cover_path, …) into the file at
  /// [filePath]. Returns the backend result map; `method` is "native"/"native_*"
  /// for formats the Go backend tags directly (FLAC/WAV/AIFF/APE), or "ffmpeg"
  /// (with a `fields` map) for lossy formats the caller must finish via FFmpeg.
  Future<Map<String, dynamic>> editFileMetadata(
    String filePath,
    Map<String, String> metadata,
  ) async {
    final raw = await _c.invokeMethod<String>('editFileMetadata', {
      'filePath': filePath,
      'metadataJson': jsonEncode(metadata),
    });
    return raw == null || raw.isEmpty
        ? {}
        : Map<String, dynamic>.from(jsonDecode(raw));
  }

  /// Re-fetches metadata/cover/lyrics for an existing local file from the
  /// configured providers and re-embeds them. [request] matches the backend
  /// reEnrichRequest shape. Returns the enriched result map.
  Future<Map<String, dynamic>> reEnrichFile(Map<String, dynamic> request) async {
    final raw = await _c.invokeMethod<String>(
      'reEnrichFile',
      {'requestJson': jsonEncode(request)},
    );
    return raw == null || raw.isEmpty
        ? {}
        : Map<String, dynamic>.from(jsonDecode(raw));
  }

  /// Runs an extension's custom (entity) search. [options] typically carries
  /// `{'filter': 'artist'|'album', 'limit': n}`. Returns entity maps
  /// ({id, name, artists, images, item_type, provider_id, ...}).
  Future<List<Map<String, dynamic>>> customSearch(
    String extensionId,
    String query, {
    Map<String, dynamic>? options,
  }) async {
    final raw = await _c.invokeMethod<String>('customSearchWithExtension', {
      'extensionId': extensionId,
      'query': query,
      'optionsJson': options == null ? '' : jsonEncode(options),
    });
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    return decoded is List
        ? decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
  }

  /// Lists installed extensions that support custom (entity) search.
  Future<List<Map<String, dynamic>>> getSearchProviders() async {
    final raw = await _c.invokeMethod<String>('getSearchProviders');
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    return decoded is List
        ? decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
  }

  Future<void> setDownloadDirectory(String path) =>
      _c.invokeMethod('setDownloadDirectory', {'path': path});

  Future<void> allowDownloadDir(String path) =>
      _c.invokeMethod('allowDownloadDir', {'path': path});

  Future<Map<String, dynamic>> checkDuplicate(String outputDir, String isrc) async {
    final raw = await _c.invokeMethod<String>(
      'checkDuplicate',
      {'outputDir': outputDir, 'isrc': isrc},
    );
    return raw == null || raw.isEmpty ? {} : Map<String, dynamic>.from(jsonDecode(raw));
  }

  Future<Map<String, dynamic>> getExtensionSettings(String id) async {
    final raw = await _c.invokeMethod<String>('getExtensionSettings', {'id': id});
    if (raw == null || raw.isEmpty) return {};
    return Map<String, dynamic>.from(jsonDecode(raw));
  }

  Future<void> setExtensionSettings(String id, Map<String, dynamic> settings) =>
      _c.invokeMethod('setExtensionSettings', {'id': id, 'settingsJson': jsonEncode(settings)});

  Future<List<String>> getDownloadPriority() async {
    final raw = await _c.invokeMethod<String>('getDownloadPriority');
    return raw == null || raw.isEmpty ? [] : (jsonDecode(raw) as List).map((e) => e.toString()).toList();
  }

  Future<void> setDownloadPriority(List<String> ids) =>
      _c.invokeMethod('setDownloadPriority', {'priorityJson': jsonEncode(ids)});

  Future<List<String>> getMetadataPriority() async {
    final raw = await _c.invokeMethod<String>('getMetadataPriority');
    return raw == null || raw.isEmpty ? [] : (jsonDecode(raw) as List).map((e) => e.toString()).toList();
  }

  Future<void> setMetadataPriority(List<String> ids) =>
      _c.invokeMethod('setMetadataPriority', {'priorityJson': jsonEncode(ids)});

  Future<ServerStatus> startMediaServer(String rootDir, String name) async {
    final raw = await _c.invokeMethod<String>(
      'startMediaServer',
      {'rootDir': rootDir, 'name': name},
    );
    if (raw == null || raw.isEmpty) return ServerStatus.stopped;
    return ServerStatus.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
  }

  Future<void> stopMediaServer() => _c.invokeMethod('stopMediaServer');

  Future<ServerStatus> getMediaServerStatus() async {
    final raw = await _c.invokeMethod<String>('getMediaServerStatus');
    if (raw == null || raw.isEmpty) return ServerStatus.stopped;
    return ServerStatus.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
  }

  /// Sets the directory where the Go library scanner caches extracted cover
  /// art. Must be called once before [scanLibraryFolder].
  Future<void> setLibraryCoverCacheDir(String cacheDir) =>
      _c.invokeMethod('setLibraryCoverCacheDir', {'cacheDir': cacheDir});

  /// Scans [folderPath] for audio files, reads their embedded tags
  /// (ID3/Vorbis/M4A), extracts cover art, and returns a list of metadata
  /// maps matching SpotiFLAC's LibraryScanResult schema.
  Future<List<Map<String, dynamic>>> scanLibraryFolder(String folderPath) async {
    final raw = await _c.invokeMethod<String>(
      'scanLibraryFolder',
      {'folderPath': folderPath},
    );
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    final list = decoded is List ? decoded : <dynamic>[];
    return list
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}

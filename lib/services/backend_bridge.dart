import 'dart:convert';
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
        : (decoded['items'] as List? ?? (decoded as Map).values.toList());
    return list.map((e) => DownloadProgress.fromJson(Map<String, dynamic>.from(e))).toList();
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
}

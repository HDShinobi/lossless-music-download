import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/download_progress.dart';
import '../models/download_request.dart';
import '../models/track.dart';
import 'download_dir_provider.dart';
import 'download_labels_provider.dart';
import 'extensions_provider.dart';

/// Real-time download progress — uses EventChannel on Android, falls back to
/// 1-second polling on other platforms. Backed by BackendBridge.progressStream().
final downloadsProvider = StreamProvider<List<DownloadProgress>>((ref) {
  final bridge = ref.read(backendBridgeProvider);
  return bridge.progressStream();
});

/// Drives download actions: resolves the output dir and calls the bridge.
class DownloadController {
  const DownloadController(this._ref);
  final Ref _ref;

  Future<void> start(Track track, {String? source, String? quality}) async {
    final dir = await _ref.read(downloadDirProvider.future);
    final bridge = _ref.read(backendBridgeProvider);
    final itemId = 'dl_${DateTime.now().microsecondsSinceEpoch}_${track.id}';
    _ref.read(downloadLabelsProvider.notifier).put(itemId, track);
    final req = DownloadRequest(
      trackName: track.name,
      artistName: track.artists,
      outputDir: dir,
      albumName: track.albumName,
      isrc: track.isrc,
      useExtensions: true,
      source: source,
      quality: quality,
      itemId: itemId,
    );
    await bridge.downloadByStrategy(req);
  }
}

final downloadControllerProvider = Provider<DownloadController>(
  (ref) => DownloadController(ref),
);

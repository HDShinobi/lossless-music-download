import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/download_progress.dart';
import '../models/download_request.dart';
import '../models/track.dart';
import 'download_dir_provider.dart';
import 'extensions_provider.dart';

/// Polls [BackendBridge.getAllProgress] every second and emits the list.
final downloadsProvider = StreamProvider<List<DownloadProgress>>((ref) async* {
  final bridge = ref.read(backendBridgeProvider);
  while (true) {
    try {
      yield await bridge.getAllProgress();
    } catch (_) {
      yield const [];
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
});

/// Drives download actions: resolves the output dir and calls the bridge.
class DownloadController {
  const DownloadController(this._ref);
  final Ref _ref;

  Future<void> start(Track track, {String? source, String? quality}) async {
    final dir = await _ref.read(downloadDirProvider.future);
    final bridge = _ref.read(backendBridgeProvider);
    final req = DownloadRequest(
      trackName: track.name,
      artistName: track.artists,
      outputDir: dir,
      albumName: track.albumName,
      isrc: track.isrc,
      useExtensions: true,
      source: source,
      quality: quality,
    );
    await bridge.downloadByStrategy(req);
  }
}

final downloadControllerProvider = Provider<DownloadController>(
  (ref) => DownloadController(ref),
);

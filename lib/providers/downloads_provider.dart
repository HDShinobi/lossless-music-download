import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/download_progress.dart';
import 'extensions_provider.dart';

/// Real-time download progress — uses EventChannel on Android, falls back to
/// 1-second polling on other platforms. Backed by BackendBridge.progressStream().
final downloadsProvider = StreamProvider<List<DownloadProgress>>((ref) {
  final bridge = ref.read(backendBridgeProvider);
  return bridge.progressStream();
});

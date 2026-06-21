import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/app_dirs.dart';
import 'extensions_provider.dart';

/// Injectable seam: resolves the raw download-directory path.
/// Override in tests to avoid hitting path_provider's platform channel.
final downloadDirPathProvider = Provider<Future<String>>(
  (_) => AppDirs.downloadDir(),
);

/// Resolves the download directory, then wires it into the backend:
///   • [BackendBridge.setDownloadDirectory] — tells the Go backend where to write files
///   • [BackendBridge.allowDownloadDir]     — grants the backend permission to that path
///
/// Override [downloadDirPathProvider] and [backendBridgeProvider] in tests to
/// keep this provider hermetic (no real path_provider or MethodChannel calls).
final downloadDirProvider = FutureProvider<String>((ref) async {
  final path = await ref.read(downloadDirPathProvider);
  final bridge = ref.read(backendBridgeProvider);
  await bridge.setDownloadDirectory(path);
  await bridge.allowDownloadDir(path);
  return path;
});

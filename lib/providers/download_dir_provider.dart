import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_dirs.dart';
import 'extensions_provider.dart';

/// SharedPreferences key holding the user-selected download directory (a real
/// filesystem path). Absent/empty means "use the platform default".
const kDownloadDirPrefKey = 'download_directory';

/// Resolves the effective download directory: the persisted custom path when
/// the user has chosen one, otherwise [fallback] (the platform default).
///
/// Pure given [prefs] and [fallback] — unit tested without platform channels.
Future<String> resolveDownloadDir(
  SharedPreferences prefs,
  Future<String> Function() fallback,
) async {
  final saved = prefs.getString(kDownloadDirPrefKey);
  if (saved != null && saved.isNotEmpty) return saved;
  return fallback();
}

/// Normalizes a directory chosen by the system picker into a real filesystem
/// path usable by the Go backend (Option 1 / All-Files-Access).
///
/// `file_picker` may hand back either a plain path (returned unchanged) or an
/// Android SAF tree URI like
/// `content://com.android.externalstorage.documents/tree/primary%3AMusic`,
/// which is decoded to `/storage/emulated/0/Music`. Returns null for URIs that
/// can't be mapped to a real path (e.g. the Downloads document provider), so
/// the caller can fall back rather than persist an unusable location.
String? normalizePickedDirectory(String picked) {
  if (picked.startsWith('/')) return picked;

  const externalStorage = 'com.android.externalstorage.documents';
  if (picked.startsWith('content://') && picked.contains('/tree/')) {
    final uri = Uri.parse(picked);
    if (uri.authority != externalStorage) return null;

    final treeSegment = picked.substring(picked.indexOf('/tree/') + 6);
    final decoded = Uri.decodeComponent(treeSegment);
    final colon = decoded.indexOf(':');
    if (colon < 0) return null;

    final volume = decoded.substring(0, colon);
    final relPath = decoded.substring(colon + 1);
    final base =
        volume == 'primary' ? '/storage/emulated/0' : '/storage/$volume';
    return relPath.isEmpty ? base : '$base/$relPath';
  }
  return null;
}

/// Injectable seam: resolves the raw download-directory path (custom or
/// default). Override in tests to avoid hitting path_provider / SharedPreferences.
final downloadDirPathProvider = Provider<Future<String>>(
  (_) async {
    final prefs = await SharedPreferences.getInstance();
    return resolveDownloadDir(prefs, AppDirs.downloadDir);
  },
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

/// Mutates the persisted download directory. After persisting, it re-resolves
/// [downloadDirProvider] so the backend is re-wired to the new location and any
/// widget watching it rebuilds.
class DownloadDirController extends Notifier<void> {
  @override
  void build() {}

  /// Persists [path] as the custom download directory and re-wires the backend.
  Future<void> setDirectory(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kDownloadDirPrefKey, path);
    // downloadDirPathProvider caches its resolved Future, so invalidate it too
    // to force a fresh read of the new pref value.
    ref.invalidate(downloadDirPathProvider);
    ref.invalidate(downloadDirProvider);
  }
}

final downloadDirControllerProvider =
    NotifierProvider<DownloadDirController, void>(DownloadDirController.new);

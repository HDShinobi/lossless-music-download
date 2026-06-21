import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/installed_extension.dart';
import '../services/backend_bridge.dart';
import '../services/app_dirs.dart';

/// Provides the [BackendBridge] instance. Override in tests to inject a fake.
final backendBridgeProvider = Provider<BackendBridge>((ref) => BackendBridge());

/// Provides the extension dirs tuple `(extDir, dataDir)`.
/// Override in tests to avoid hitting path_provider's platform channel.
final appDirsProvider = Provider<Future<(String, String)>>(
  (_) => AppDirs.extensionDirs(),
);

class ExtensionsController extends AsyncNotifier<List<InstalledExtension>> {
  BackendBridge get _b => ref.read(backendBridgeProvider);

  @override
  Future<List<InstalledExtension>> build() async {
    final (ext, data) = await ref.read(appDirsProvider);
    await _b.initExtensionSystem(ext, data);
    return _b.getInstalledExtensions();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _b.getInstalledExtensions());
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await _b.setExtensionEnabled(id, enabled);
    await refresh();
  }

  Future<void> remove(String id) async {
    await _b.removeExtension(id);
    await refresh();
  }
}

final extensionsProvider =
    AsyncNotifierProvider<ExtensionsController, List<InstalledExtension>>(
  ExtensionsController.new,
);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/server_status.dart';
import '../providers/extensions_provider.dart';
import '../providers/download_dir_provider.dart';

class ServerStartError extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? error) => state = error;
}

final serverStartErrorProvider = NotifierProvider<ServerStartError, String?>(
  ServerStartError.new,
);

class ServerController extends AsyncNotifier<ServerStatus> {
  bool _refreshing = false;
  int _revision = 0;

  @override
  Future<ServerStatus> build() =>
      ref.read(backendBridgeProvider).getMediaServerStatus();

  Future<void> refreshStatus() async {
    if (_refreshing || state.isLoading) return;
    _refreshing = true;
    final revision = _revision;
    try {
      final status = await ref
          .read(backendBridgeProvider)
          .getMediaServerStatus();
      if (revision == _revision) state = AsyncData(status);
    } catch (error, stackTrace) {
      if (revision == _revision) state = AsyncError(error, stackTrace);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> start() async {
    _revision++;
    state = const AsyncLoading();
    try {
      final dir = await ref.read(downloadDirProvider.future);
      final result = await ref
          .read(backendBridgeProvider)
          .startMediaServer(dir, 'Lossless Music');
      _revision++;
      ref.read(serverStartErrorProvider.notifier).set(null);
      state = AsyncData(result);
    } catch (e, st) {
      _revision++;
      ref.read(serverStartErrorProvider.notifier).set(e.toString());
      state = AsyncError(e, st);
    }
  }

  Future<void> stop() async {
    _revision++;
    ref.read(serverStartErrorProvider.notifier).set(null);
    await ref.read(backendBridgeProvider).stopMediaServer();
    _revision++;
    state = const AsyncData(ServerStatus.stopped);
  }
}

final serverProvider = AsyncNotifierProvider<ServerController, ServerStatus>(
  ServerController.new,
);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/server_status.dart';
import '../providers/extensions_provider.dart';
import '../providers/download_dir_provider.dart';

class ServerController extends AsyncNotifier<ServerStatus> {
  @override
  Future<ServerStatus> build() =>
      ref.read(backendBridgeProvider).getMediaServerStatus();

  Future<void> start() async {
    state = const AsyncLoading();
    try {
      final dir = await ref.read(downloadDirProvider.future);
      final result = await ref
          .read(backendBridgeProvider)
          .startMediaServer(dir, 'Lossless Music');
      state = AsyncData(result);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> stop() async {
    await ref.read(backendBridgeProvider).stopMediaServer();
    state = const AsyncData(ServerStatus.stopped);
  }
}

final serverProvider =
    AsyncNotifierProvider<ServerController, ServerStatus>(ServerController.new);

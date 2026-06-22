import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/server_status.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/server_provider.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';

// ---------------------------------------------------------------------------
// Fake bridge — overrides only media-server methods; no real MethodChannel.
// ---------------------------------------------------------------------------
class _FakeBridge extends BackendBridge {
  ServerStatus _statusToReturn = ServerStatus.stopped;
  bool stopCalled = false;

  void setStatus(ServerStatus s) => _statusToReturn = s;

  @override
  Future<ServerStatus> getMediaServerStatus() async => _statusToReturn;

  @override
  Future<ServerStatus> startMediaServer(String rootDir, String name) async =>
      _statusToReturn;

  @override
  Future<void> stopMediaServer() async => stopCalled = true;

  // downloadDirProvider calls these — provide no-op overrides
  @override
  Future<void> setDownloadDirectory(String path) async {}

  @override
  Future<void> allowDownloadDir(String path) async {}
}

void main() {
  group('ServerProvider', () {
    ProviderContainer makeContainer(_FakeBridge fake) {
      return ProviderContainer(
        overrides: [
          backendBridgeProvider.overrideWithValue(fake),
          downloadDirPathProvider.overrideWithValue(Future.value('/test/downloads')),
        ],
      );
    }

    test('build() → stopped by default', () async {
      final fake = _FakeBridge();
      // fake already has stopped as default
      final container = makeContainer(fake);
      addTearDown(container.dispose);

      final status = await container.read(serverProvider.future);
      expect(status.running, isFalse);
    });

    test('start() → state running=true with url', () async {
      final fake = _FakeBridge();
      const running = ServerStatus(
        running: true,
        url: 'http://10.0.0.5:8200/',
        name: 'Lossless Music',
      );
      final container = makeContainer(fake);
      addTearDown(container.dispose);

      // Ensure build is done first
      await container.read(serverProvider.future);

      // Now set what startMediaServer should return
      fake.setStatus(running);

      await container.read(serverProvider.notifier).start();

      final status = container.read(serverProvider).value;
      expect(status, isNotNull);
      expect(status!.running, isTrue);
      expect(status.url, 'http://10.0.0.5:8200/');
    });

    test('stop() → running=false', () async {
      final fake = _FakeBridge();
      const running = ServerStatus(
        running: true,
        url: 'http://10.0.0.5:8200/',
        name: 'Lossless Music',
      );
      final container = makeContainer(fake);
      addTearDown(container.dispose);

      // Start in running state
      fake.setStatus(running);
      await container.read(serverProvider.future);
      await container.read(serverProvider.notifier).start();

      // Now stop
      await container.read(serverProvider.notifier).stop();

      final status = container.read(serverProvider).value;
      expect(status, isNotNull);
      expect(status!.running, isFalse);
      expect(fake.stopCalled, isTrue);
    });
  });
}

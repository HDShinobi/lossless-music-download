import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';

// ---------------------------------------------------------------------------
// Fake bridge — records setDownloadDirectory / allowDownloadDir calls without
// hitting any real MethodChannel.
// ---------------------------------------------------------------------------
class FakeBackendBridge extends BackendBridge {
  final List<String> setDirCalls = [];
  final List<String> allowDirCalls = [];

  @override
  Future<void> setDownloadDirectory(String path) async {
    setDirCalls.add(path);
  }

  @override
  Future<void> allowDownloadDir(String path) async {
    allowDirCalls.add(path);
  }
}

void main() {
  const testPath = '/tmp/test_dl';

  group('downloadDirProvider', () {
    test('returns injected path and records both bridge calls', () async {
      final fake = FakeBackendBridge();

      final container = ProviderContainer(
        overrides: [
          // Stub path resolution — no path_provider platform channel needed.
          downloadDirPathProvider.overrideWithValue(Future.value(testPath)),
          // Inject fake bridge — no MethodChannel calls needed.
          backendBridgeProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(downloadDirProvider.future);

      expect(result, testPath);
      expect(fake.setDirCalls, [testPath]);
      expect(fake.allowDirCalls, [testPath]);
    });
  });
}

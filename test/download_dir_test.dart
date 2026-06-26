import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  group('resolveDownloadDir', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('returns the persisted custom path when one is saved', () async {
      SharedPreferences.setMockInitialValues({
        kDownloadDirPrefKey: '/storage/emulated/0/Music/Lossless',
      });
      final prefs = await SharedPreferences.getInstance();
      var fallbackCalled = false;

      final result = await resolveDownloadDir(prefs, () async {
        fallbackCalled = true;
        return '/app/default';
      });

      expect(result, '/storage/emulated/0/Music/Lossless');
      expect(fallbackCalled, isFalse,
          reason: 'fallback must not run when a custom path is saved');
    });

    test('falls back to the platform default when nothing is saved', () async {
      final prefs = await SharedPreferences.getInstance();

      final result =
          await resolveDownloadDir(prefs, () async => '/app/default');

      expect(result, '/app/default');
    });

    test('treats an empty saved string as unset', () async {
      SharedPreferences.setMockInitialValues({kDownloadDirPrefKey: ''});
      final prefs = await SharedPreferences.getInstance();

      final result =
          await resolveDownloadDir(prefs, () async => '/app/default');

      expect(result, '/app/default');
    });
  });

  group('normalizePickedDirectory', () {
    test('returns a plain filesystem path unchanged', () {
      expect(
        normalizePickedDirectory('/storage/emulated/0/Music/Lossless'),
        '/storage/emulated/0/Music/Lossless',
      );
    });

    test('maps a primary-volume SAF tree URI to a real path', () {
      expect(
        normalizePickedDirectory(
            'content://com.android.externalstorage.documents/tree/primary%3AMusic%2FLossless'),
        '/storage/emulated/0/Music/Lossless',
      );
    });

    test('maps the primary volume root (no subpath)', () {
      expect(
        normalizePickedDirectory(
            'content://com.android.externalstorage.documents/tree/primary%3A'),
        '/storage/emulated/0',
      );
    });

    test('maps a non-primary (SD card) volume by its id', () {
      expect(
        normalizePickedDirectory(
            'content://com.android.externalstorage.documents/tree/1A2B-3C4D%3AMusic'),
        '/storage/1A2B-3C4D/Music',
      );
    });

    test('returns null for a URI it cannot map to a real path', () {
      expect(
        normalizePickedDirectory(
            'content://com.android.providers.downloads.documents/tree/downloads'),
        isNull,
      );
    });
  });

  group('DownloadDirController.setDirectory', () {
    test('persists the new path and re-wires the backend to it', () async {
      SharedPreferences.setMockInitialValues({kDownloadDirPrefKey: '/old'});
      final fake = FakeBackendBridge();

      final container = ProviderContainer(
        overrides: [backendBridgeProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      // Initial resolution uses the previously-saved path.
      expect(await container.read(downloadDirProvider.future), '/old');
      expect(fake.setDirCalls, ['/old']);

      await container
          .read(downloadDirControllerProvider.notifier)
          .setDirectory('/storage/emulated/0/Music/Lossless');

      // The pref is written and the provider re-resolves to the new path,
      // re-issuing the backend wiring calls.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kDownloadDirPrefKey),
          '/storage/emulated/0/Music/Lossless');
      expect(await container.read(downloadDirProvider.future),
          '/storage/emulated/0/Music/Lossless');
      expect(fake.setDirCalls.last, '/storage/emulated/0/Music/Lossless');
      expect(fake.allowDirCalls.last, '/storage/emulated/0/Music/Lossless');
    });
  });
}

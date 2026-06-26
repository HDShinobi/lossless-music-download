import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/library_provider.dart';
import 'package:lossless_music_download/screens/library_screen.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';

// ---------------------------------------------------------------------------
// Fake bridge — returns scan results built from real files on disk,
// bypassing the native method channel.
// ---------------------------------------------------------------------------
const _audioExts = {'.flac', '.m4a', '.mp3', '.alac', '.wav', '.aiff', '.ogg', '.opus'};

class _FakeScanBridge extends BackendBridge {
  _FakeScanBridge(this._dir) : super(const MethodChannel('_fake'));
  final String _dir;

  @override
  Future<void> setLibraryCoverCacheDir(String cacheDir) async {}

  @override
  Future<List<Map<String, dynamic>>> scanLibraryFolder(String folderPath) async {
    final d = Directory(folderPath);
    return d
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) {
          final ext = '.${f.path.split('.').last.toLowerCase()}';
          return _audioExts.contains(ext);
        })
        .map((f) {
          final name = f.uri.pathSegments.last;
          final title = name.contains('.')
              ? name.substring(0, name.lastIndexOf('.'))
              : name;
          return <String, dynamic>{
            'filePath': f.path,
            'trackName': title,
            'artistName': '',
            'albumName': '',
            'coverPath': '',
            'duration': 0,
          };
        })
        .toList();
  }
}

Widget buildLibraryScreen(List<dynamic> overrides) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale('en'),
      home: LibraryScreen(),
    ),
  );
}

void main() {
  group('LibraryScreen widget tests (hermetic)', () {
    testWidgets('shows entries and count header when library has files',
        (tester) async {
      await tester.pumpWidget(
        buildLibraryScreen([
          libraryProvider.overrideWith(
            (_) async => [
              const LibraryEntry(
                  path: '/x/a.flac',
                  name: 'a.flac',
                  sizeBytes: 2097152,
                  format: 'FLAC',
                  verified: true),
              const LibraryEntry(
                  path: '/x/b.flac',
                  name: 'b.flac',
                  sizeBytes: 1048576,
                  format: 'FLAC',
                  verified: true),
            ],
          ),
        ]),
      );
      await tester.pumpAndSettle();

      // Count header: "2 files" (en)
      expect(find.text('2 files'), findsOneWidget);
      // Entry names (stripped of extension via LibraryTrackTile._displayName)
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
    });

    testWidgets('shows libraryEmpty when library is empty', (tester) async {
      await tester.pumpWidget(
        buildLibraryScreen([
          libraryProvider.overrideWith((_) async => []),
        ]),
      );
      await tester.pumpAndSettle();

      // en libraryEmpty = "No downloads yet."
      expect(find.text('No downloads yet.'), findsOneWidget);
    });
  });

  group('libraryProvider integration test', () {
    test('lists audio files, excludes non-audio', () async {
      final tempDir = Directory.systemTemp.createTempSync('library_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      // Create two .flac files and one .txt file
      File('${tempDir.path}/song1.flac').writeAsBytesSync([0, 1, 2]);
      File('${tempDir.path}/song2.flac').writeAsBytesSync([3, 4, 5, 6]);
      File('${tempDir.path}/readme.txt').writeAsStringSync('hello');

      // Fake bridge whose scanLibraryFolder mimics the Go scanner output
      // without real method channels or native code.
      final fakeBridge = _FakeScanBridge(tempDir.path);

      final coverCacheDir =
          Directory.systemTemp.createTempSync('cover_cache_');
      addTearDown(() => coverCacheDir.deleteSync(recursive: true));

      final container = ProviderContainer(
        overrides: [
          downloadDirProvider.overrideWith((_) async => tempDir.path),
          backendBridgeProvider.overrideWithValue(fakeBridge),
          libraryCoverCacheDirProvider
              .overrideWithValue(Future.value(coverCacheDir.path)),
        ],
      );
      addTearDown(container.dispose);

      final entries = await container.read(libraryProvider.future);
      expect(entries.length, 2);
      final names = entries.map((e) => e.name).toList()..sort();
      expect(names, ['song1.flac', 'song2.flac']);
    });
  });
}

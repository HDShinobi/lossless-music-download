import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/library_provider.dart';
import 'package:lossless_music_download/screens/library_screen.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:lossless_music_download/widgets/library_track_tile.dart';

// Fake bridge that returns one ALAC entry for the ALAC integration test.
class _AlacFakeBridge extends BackendBridge {
  _AlacFakeBridge(this._dir) : super(const MethodChannel('_fake'));
  final String _dir;

  @override
  Future<void> setLibraryCoverCacheDir(String cacheDir) async {}

  @override
  Future<List<Map<String, dynamic>>> scanLibraryFolder(String folderPath) async {
    final alacFile = File('$_dir/01. Track.alac');
    return [
      <String, dynamic>{
        'filePath': alacFile.path,
        'trackName': '01. Track',
        'artistName': '',
        'albumName': '',
        'coverPath': '',
        'duration': 0,
      },
    ];
  }
}

const albumEntry1 = LibraryEntry(
  path: '/downloads/ArtistA/AlbumOne/01 Track One.flac',
  name: '01 Track One.flac',
  sizeBytes: 5000000,
  artistName: 'ArtistA',
  albumName: 'AlbumOne',
  format: 'FLAC',
  verified: true,
);

const albumEntry2 = LibraryEntry(
  path: '/downloads/ArtistB/AlbumTwo/01 Track Two.flac',
  name: '01 Track Two.flac',
  sizeBytes: 4000000,
  artistName: 'ArtistB',
  albumName: 'AlbumTwo',
  format: 'FLAC',
  verified: true,
);

const singleEntry = LibraryEntry(
  path: '/downloads/Single Track.mp3',
  name: 'Single Track.mp3',
  sizeBytes: 3000000,
  artistName: null,
  albumName: null,
  format: 'MP3',
  verified: false,
);

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const LibraryScreen(),
    ),
    GoRoute(
      path: '/server',
      builder: (context, state) => const Scaffold(body: Text('Server')),
    ),
  ],
);

Widget buildLibraryScreen(List<dynamic> overrides) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp.router(
      routerConfig: _router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: ThemeData(useMaterial3: true),
    ),
  );
}

void main() {
  group('libraryProvider ALAC integration', () {
    test('LibraryEntry.verified is true and format is ALAC for .alac file',
        () async {
      final tempDir =
          Directory.systemTemp.createTempSync('library_alac_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      // Create a single .alac file so the scanner returns exactly one entry.
      File('${tempDir.path}/01. Track.alac').writeAsBytesSync([0, 1, 2]);

      // Minimal fake bridge: returns one ALAC entry and no-ops cover cache.
      final fakeBridge = _AlacFakeBridge(tempDir.path);

      final coverCacheDir =
          Directory.systemTemp.createTempSync('cover_cache_alac_');
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
      expect(entries.length, 1);
      expect(entries.first.format, 'ALAC');
      expect(entries.first.verified, isTrue);
    });
  });

  group('LibraryScreen (new) widget tests', () {
    testWidgets('All segment (default): all 3 track names visible',
        (tester) async {
      await tester.pumpWidget(
        buildLibraryScreen([
          libraryProvider.overrideWith(
            (_) async => [albumEntry1, albumEntry2, singleEntry],
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Track One'), findsOneWidget);
      expect(find.text('Track Two'), findsOneWidget);
      expect(find.text('Single Track'), findsOneWidget);
    });

    testWidgets(
        'Albums segment: group headers visible, single track NOT visible',
        (tester) async {
      await tester.pumpWidget(
        buildLibraryScreen([
          libraryProvider.overrideWith(
            (_) async => [albumEntry1, albumEntry2, singleEntry],
          ),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Albums'));
      await tester.pumpAndSettle();

      expect(find.text('AlbumOne'), findsOneWidget);
      expect(find.text('AlbumTwo'), findsOneWidget);
      expect(find.text('Single Track'), findsNothing);
    });

    testWidgets(
        'Singles segment: only single track visible, group headers NOT visible',
        (tester) async {
      await tester.pumpWidget(
        buildLibraryScreen([
          libraryProvider.overrideWith(
            (_) async => [albumEntry1, albumEntry2, singleEntry],
          ),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Singles'));
      await tester.pumpAndSettle();

      expect(find.text('Single Track'), findsOneWidget);
      expect(find.text('AlbumOne'), findsNothing);
      expect(find.text('AlbumTwo'), findsNothing);
    });

    testWidgets('library search filters by title', (tester) async {
      await tester.pumpWidget(
        buildLibraryScreen([
          libraryProvider.overrideWith(
            (_) async => [albumEntry1, albumEntry2, singleEntry],
          ),
        ]),
      );
      await tester.pumpAndSettle();

      // Search for 'Track One' - should find only albumEntry1
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, 'Track One');
      await tester.pumpAndSettle();

      // Should find Track One in results (only in the tile, not in the input field)
      // Note: TextField will contain 'Track One' too, so check for the tile text
      expect(find.byType(LibraryTrackTile), findsOneWidget);
      expect(find.text('Track Two'), findsNothing);
      expect(find.text('Single Track'), findsNothing);
    });
  });
}

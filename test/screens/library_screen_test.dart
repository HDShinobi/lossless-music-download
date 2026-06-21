import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/providers/library_provider.dart';
import 'package:lossless_music_download/screens/library_screen.dart';

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
  });
}

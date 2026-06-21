import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/library_provider.dart';
import 'package:lossless_music_download/screens/library_screen.dart';

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
              const LibraryEntry('/x/a.flac', 'a.flac', 2097152),
              const LibraryEntry('/x/b.flac', 'b.flac', 1048576),
            ],
          ),
        ]),
      );
      await tester.pumpAndSettle();

      // Count header: "2 files" (en)
      expect(find.text('2 files'), findsOneWidget);
      // Entry names
      expect(find.text('a.flac'), findsOneWidget);
      expect(find.text('b.flac'), findsOneWidget);
      // Sizes in MB
      expect(find.text('2.0 MB'), findsOneWidget);
      expect(find.text('1.0 MB'), findsOneWidget);
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

      final container = ProviderContainer(
        overrides: [
          // Override the whole downloadDirProvider to skip bridge calls
          downloadDirProvider.overrideWith((_) async => tempDir.path),
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

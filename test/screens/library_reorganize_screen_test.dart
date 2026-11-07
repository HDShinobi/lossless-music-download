import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/download_history_provider.dart';
import 'package:lossless_music_download/providers/library_provider.dart';
import 'package:lossless_music_download/providers/download_queue_provider.dart';
import 'package:lossless_music_download/screens/library_reorganize_screen.dart';
import 'package:lossless_music_download/services/history_database.dart';

class _Queue extends DownloadQueueController {
  @override
  List<DownloadEntry> build() => [];
}

void main() {
  sqfliteFfiInit();
  late Directory root;
  late HistoryDatabase db;
  late File file;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'filename_template': '{title}'});
    root = await Directory.systemTemp.createTemp('c3_ui_');
    db = HistoryDatabase(
      path: '${root.path}/history.db',
      factory: databaseFactoryFfi,
    );
    file = File('${root.path}/old.flac');
    await file.writeAsString('audio');
    await db.upsert(
      HistoryEntry(
        id: 'one',
        track: const Track(
          id: 'qobuz:1',
          name: 'Song',
          artists: 'Artist',
          albumName: 'Album',
        ),
        service: 'qobuz',
        filePath: file.path,
        downloadedAt: DateTime(2026),
      ),
    );
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  testWidgets(
    'preview does not move until apply, then reports result and history path',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            downloadQueueProvider.overrideWith(_Queue.new),
            historyDatabaseProvider.overrideWith((_) async => db),
            downloadDirProvider.overrideWith((_) async => root.path),
            libraryProvider.overrideWith((_) async => []),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LibraryReorganizeScreen(),
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
        if (find.text('Apply changes').evaluate().isNotEmpty) break;
      }
      expect(find.textContaining('old.flac'), findsOneWidget);
      expect(await tester.runAsync(file.exists), isTrue);
      await tester.tap(find.text('Apply changes'));
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
        if (find.textContaining('1 moved').evaluate().isNotEmpty) break;
      }
      expect(
        find.textContaining('1 moved'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .join(' | '),
      );
      expect(
        (await tester.runAsync(db.list))!.single.filePath,
        '${root.path}/Artist/Album/Song.flac',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}

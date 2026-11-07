import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/providers/download_history_provider.dart';
import 'package:lossless_music_download/screens/download_history_screen.dart';
import 'package:lossless_music_download/services/history_database.dart';

// UI tests keep storage synchronous; SQLite CRUD/migrations use real FFI in
// services/history_database_test.dart.
class _MemoryHistory extends HistoryDatabase {
  _MemoryHistory() : super(path: 'unused');
  final rows = <HistoryEntry>[];
  @override
  Future<void> upsert(HistoryEntry entry) async => rows.add(entry);
  @override
  Future<List<HistoryEntry>> list({
    String search = '',
    int limit = 100,
    int offset = 0,
  }) async => rows
      .where(
        (e) => '${e.track.name} ${e.track.artists}'.toLowerCase().contains(
          search.toLowerCase(),
        ),
      )
      .toList();
  @override
  Future<void> remove(String id) async => rows.removeWhere((e) => e.id == id);
}

void main() {
  testWidgets(
    'history searches title/artist and removes entry without deleting audio',
    (tester) async {
      late Directory dir;
      late HistoryDatabase db;
      late File file;
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('history_ui_');
        db = _MemoryHistory();
        file = await File('${dir.path}/song.flac').writeAsString('audio');
        await db.upsert(
          HistoryEntry(
            id: 'one',
            track: const Track(
              id: '1',
              name: 'First song',
              artists: 'Artist One',
            ),
            service: 'qobuz',
            filePath: file.path,
            downloadedAt: DateTime(2026),
          ),
        );
      });
      final c = ProviderContainer(
        overrides: [historyDatabaseProvider.overrideWith((ref) async => db)],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const DownloadHistoryScreen(),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('First song'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Missing');
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('First song'), findsNothing);
      await tester.enterText(find.byType(TextField), 'artist one');
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('First song'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove entry'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('First song'), findsNothing);
      await tester.runAsync(() async {
        expect(await file.exists(), isTrue);
        c.dispose();
        await db.close();
        await dir.delete(recursive: true);
      });
    },
  );
}

import 'dart:io';
import 'dart:async';
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
import 'package:lossless_music_download/providers/batch_re_enrich_provider.dart';
import 'package:lossless_music_download/providers/library_busy_provider.dart';
import '../helpers/library_queue_fake.dart';

class _Queue extends DownloadQueueController {
  @override
  List<DownloadEntry> build() => [];
}

class _RunningBatch extends BatchReEnrich {
  @override
  BatchReEnrichState build() => const BatchReEnrichState(running: true);
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
  testWidgets('queue arriving while preview loads prevents planning recovery', (
    tester,
  ) async {
    final tags = Completer<List<LibraryEntry>>();
    var tagsRequested = false;
    final container = ProviderContainer(
      overrides: [
        downloadQueueProvider.overrideWith(LibraryQueueFake.new),
        historyDatabaseProvider.overrideWith((_) async => db),
        downloadDirProvider.overrideWith((_) async => root.path),
        libraryProvider.overrideWith((_) {
          tagsRequested = true;
          return tags.future;
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LibraryReorganizeScreen(),
        ),
      ),
    );
    for (var i = 0; i < 30 && !tagsRequested; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(tagsRequested, isTrue);
    expect(container.read(libraryReorganizeRunningProvider), isTrue);
    (container.read(downloadQueueProvider.notifier) as LibraryQueueFake)
        .replace([queueEntry('processing')]);
    tags.complete([]);
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (!container.read(libraryReorganizeRunningProvider)) break;
    }
    expect(
      find.textContaining('Wait for downloads and file updates'),
      findsOneWidget,
    );
    expect(find.text('Apply changes'), findsNothing);
    expect(container.read(libraryReorganizeRunningProvider), isFalse);
    expect(file.existsSync(), isTrue);
  });
  for (final batchRunning in [false, true]) {
    testWidgets(
      'reorganize refuses ${batchRunning ? 'batch' : 'queue'} activity',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            downloadQueueProvider.overrideWith(LibraryQueueFake.new),
            if (batchRunning)
              batchReEnrichProvider.overrideWith(_RunningBatch.new),
          ],
        );
        addTearDown(container.dispose);
        if (!batchRunning) {
          (container.read(downloadQueueProvider.notifier) as LibraryQueueFake)
              .replace([queueEntry('paused')]);
        }
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: LibraryReorganizeScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Wait for downloads and file updates'),
          findsOneWidget,
        );
        expect(find.text('Apply changes'), findsNothing);
        expect(container.read(libraryReorganizeRunningProvider), isFalse);
        expect(file.existsSync(), isTrue);
      },
    );
  }
  testWidgets(
    'preview does not move until apply, then reports result and history path',
    (tester) async {
      final runningStates = <bool>[];
      final container = ProviderContainer(
        overrides: [
          downloadQueueProvider.overrideWith(_Queue.new),
          historyDatabaseProvider.overrideWith((_) async => db),
          downloadDirProvider.overrideWith((_) async => root.path),
          libraryProvider.overrideWith((_) async => []),
        ],
      );
      addTearDown(container.dispose);
      container.listen(
        libraryReorganizeRunningProvider,
        (_, value) => runningStates.add(value),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
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
      expect(runningStates, [true, false, true, false]);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

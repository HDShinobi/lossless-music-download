import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/providers/batch_re_enrich_provider.dart';
import 'package:lossless_music_download/providers/download_history_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/library_provider.dart';
import 'package:lossless_music_download/screens/library_album_screen.dart';
import 'package:lossless_music_download/screens/library_screen.dart';
import '../helpers/re_enrich_fakes.dart';
import '../helpers/library_queue_fake.dart';
import 'package:lossless_music_download/providers/download_queue_provider.dart';
import 'package:lossless_music_download/providers/library_busy_provider.dart';
import 'package:lossless_music_download/widgets/library_track_tile.dart';

const _one = LibraryEntry(
  path: '/1.flac',
  name: 'One.flac',
  sizeBytes: 0,
  title: 'One',
  artistName: 'A',
  albumName: 'Album',
  format: 'FLAC',
  verified: true,
);
const _two = LibraryEntry(
  path: '/2.flac',
  name: 'Two.flac',
  sizeBytes: 0,
  title: 'Two',
  artistName: 'B',
  albumName: 'Other',
  format: 'FLAC',
  verified: true,
);
void main() {
  testWidgets('queue disables selected and album refresh with a busy hint', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        downloadQueueProvider.overrideWith(LibraryQueueFake.new),
        libraryProvider.overrideWith((_) async => [_one]),
      ],
    );
    addTearDown(container.dispose);
    final queue =
        container.read(downloadQueueProvider.notifier) as LibraryQueueFake;
    queue.replace([queueEntry('processing')]);
    Widget app(Widget screen) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: screen,
      ),
    );
    await tester.pumpWidget(app(const LibraryScreen()));
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(LibraryTrackTile));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(TextButton, 'Refresh metadata');
    expect(tester.widget<TextButton>(button).onPressed, isNull);
    expect(
      find.text('Library busy. Wait for downloads or file updates to finish.'),
      findsOneWidget,
    );
    queue.replace([queueEntry('done')]);
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    final reorganize = container.read(
      libraryReorganizeRunningProvider.notifier,
    );
    expect(reorganize.tryStart(), isTrue);
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(button).onPressed, isNull);
    reorganize.finish();
    queue.replace([queueEntry('queued')]);
    await tester.pumpWidget(
      app(const LibraryAlbumScreen(artistName: 'A', albumName: 'Album')),
    );
    await tester.pumpAndSettle();
    final albumButton = find.byIcon(Icons.auto_fix_high);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(of: albumButton, matching: find.byType(IconButton)),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.byTooltip(
        'Library busy. Wait for downloads or file updates to finish.',
      ),
      findsOneWidget,
    );
  });
  testWidgets(
    'album refresh survives screen disposal and results show per-file failures',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final bridge = FakeBridge()..gate = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          backendBridgeProvider.overrideWithValue(bridge),
          historyDatabaseProvider.overrideWith((_) async => FakeHistory()),
          libraryProvider.overrideWith((_) async => [_one, _two]),
        ],
      );
      addTearDown(container.dispose);
      Widget app(Widget screen) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: screen,
        ),
      );
      await tester.pumpWidget(
        app(const LibraryAlbumScreen(artistName: 'A', albumName: 'Album')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Refresh album'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(container.read(batchReEnrichProvider).total, 1);
      await tester.pumpWidget(app(const Scaffold(body: Text('Away'))));
      bridge.gate!.complete();
      await tester.pumpAndSettle();
      expect(container.read(batchReEnrichProvider).completed, 1);
      expect(bridge.requests.map((r) => r['file_path']).toSet(), {'/1.flac'});
      await tester.pumpWidget(app(const LibraryScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Metadata refreshed'), findsOneWidget);
      unawaited(container.read(batchReEnrichProvider.notifier).start([_two]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View failures'));
      await tester.pumpAndSettle();
      expect(find.text('Two'), findsWidgets);
      expect(find.textContaining('lookup failed'), findsOneWidget);
    },
  );
}

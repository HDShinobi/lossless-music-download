import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/theme/app_theme.dart';
import 'package:lossless_music_download/widgets/download_sheet.dart';

// ---------------------------------------------------------------------------
// Helper: build a minimal InstalledExtension for testing
// ---------------------------------------------------------------------------
InstalledExtension _fakeSource({
  required String id,
  required String displayName,
  bool enabled = true,
}) =>
    InstalledExtension(
      id: id,
      name: id,
      displayName: displayName,
      version: '1.0.0',
      description: '',
      status: 'active',
      enabled: enabled,
      types: const ['download'],
      permissions: const [],
      hasMetadataProvider: false,
      hasDownloadProvider: true,
      hasLyricsProvider: false,
    );

const _track = Track(id: '1', name: 'Bohemian Rhapsody', artists: 'Queen');

Future<DownloadChoice?> _pumpAndShowSheet(
  WidgetTester tester,
  List<InstalledExtension> sources,
) async {
  DownloadChoice? result;

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: appTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showDownloadSheet(
                  context,
                  track: _track,
                  sources: sources,
                );
              },
              child: const Text('Open sheet'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open sheet'));
  await tester.pumpAndSettle();

  return result;
}

void main() {
  group('DownloadSheet', () {
    testWidgets('renders source chips for each source', (tester) async {
      final sources = [
        _fakeSource(id: 'deezer', displayName: 'Deezer'),
        _fakeSource(id: 'tidal', displayName: 'Tidal'),
      ];
      await _pumpAndShowSheet(tester, sources);

      expect(find.text('Deezer'), findsOneWidget);
      expect(find.text('Tidal'), findsOneWidget);
    });

    testWidgets('renders quality radio options', (tester) async {
      final sources = [_fakeSource(id: 'deezer', displayName: 'Deezer')];
      await _pumpAndShowSheet(tester, sources);

      expect(find.text('FLAC · Hi-Res'), findsOneWidget);
      expect(find.text('FLAC · CD'), findsOneWidget);
      expect(find.text('MP3'), findsOneWidget);
    });

    testWidgets('renders the CTA button', (tester) async {
      final sources = [_fakeSource(id: 'deezer', displayName: 'Deezer')];
      await _pumpAndShowSheet(tester, sources);

      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('tapping CTA returns first source and first quality by default',
        (tester) async {
      final sources = [
        _fakeSource(id: 'deezer', displayName: 'Deezer'),
        _fakeSource(id: 'tidal', displayName: 'Tidal'),
      ];
      DownloadChoice? result;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: appTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    result = await showDownloadSheet(
                      context,
                      track: _track,
                      sources: sources,
                    );
                  },
                  child: const Text('Open sheet'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open sheet'));
      await tester.pumpAndSettle();

      // Tap CTA without changing selection
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.sourceId, 'deezer');
      expect(result!.quality, 'hires');
    });

    testWidgets('tapping second source chip changes sourceId in result',
        (tester) async {
      final sources = [
        _fakeSource(id: 'deezer', displayName: 'Deezer'),
        _fakeSource(id: 'tidal', displayName: 'Tidal'),
      ];
      DownloadChoice? result;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: appTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    result = await showDownloadSheet(
                      context,
                      track: _track,
                      sources: sources,
                    );
                  },
                  child: const Text('Open sheet'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open sheet'));
      await tester.pumpAndSettle();

      // Select Tidal
      await tester.tap(find.text('Tidal'));
      await tester.pumpAndSettle();

      // Select MP3 quality
      await tester.tap(find.text('MP3'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      expect(result!.sourceId, 'tidal');
      expect(result!.quality, 'mp3');
    });

    testWidgets('cancelling sheet returns null', (tester) async {
      final sources = [_fakeSource(id: 'deezer', displayName: 'Deezer')];
      DownloadChoice? result;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: appTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    result = await showDownloadSheet(
                      context,
                      track: _track,
                      sources: sources,
                    );
                  },
                  child: const Text('Open sheet'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open sheet'));
      await tester.pumpAndSettle();

      // Dismiss by tapping outside
      await tester.tapAt(const Offset(200, 100));
      await tester.pumpAndSettle();

      // result is the awaited value — null means it was not set (cancelled)
      expect(result, isNull);
    });
  });
}

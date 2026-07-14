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
  List<ExtensionQualityOption> qualityOptions = const [],
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
      qualityOptions: qualityOptions,
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

    testWidgets('empty sources: shows hint and disables the CTA',
        (tester) async {
      await _pumpAndShowSheet(tester, const []);

      expect(
        find.text('No download source yet. Install one in Discover.'),
        findsOneWidget,
      );
      // CTA present but disabled (onPressed == null).
      final cta = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Download'),
      );
      expect(cta.onPressed, isNull);
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

    testWidgets(
        'shows the selected source\'s own quality options when it declares them',
        (tester) async {
      final sources = [
        _fakeSource(id: 'tidal', displayName: 'Tidal', qualityOptions: const [
          ExtensionQualityOption(
              id: 'HI_RES_LOSSLESS', label: 'Hi-Res FLAC', description: '24-bit / 192 kHz'),
          ExtensionQualityOption(
              id: 'LOSSLESS', label: 'FLAC Lossless', description: '16-bit / 44.1 kHz'),
        ]),
      ];
      await _pumpAndShowSheet(tester, sources);

      // Source-declared options are shown...
      expect(find.text('Hi-Res FLAC'), findsOneWidget);
      expect(find.text('FLAC Lossless'), findsOneWidget);
      // ...and the hardcoded fallback ones are NOT.
      expect(find.text('FLAC · Hi-Res'), findsNothing);
      expect(find.text('MP3'), findsNothing);
    });

    testWidgets(
        'CTA returns the extension quality id for a source with options',
        (tester) async {
      final sources = [
        _fakeSource(id: 'tidal', displayName: 'Tidal', qualityOptions: const [
          ExtensionQualityOption(id: 'HI_RES_LOSSLESS', label: 'Hi-Res FLAC'),
          ExtensionQualityOption(id: 'LOSSLESS', label: 'FLAC Lossless'),
        ]),
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
                    result = await showDownloadSheet(context,
                        track: _track, sources: sources);
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

      // Pick the second option, then download.
      await tester.tap(find.text('FLAC Lossless'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      expect(result!.sourceId, 'tidal');
      expect(result!.quality, 'LOSSLESS');
    });

    testWidgets(
        'switching sources swaps the quality list and resets the selection',
        (tester) async {
      final sources = [
        _fakeSource(id: 'tidal', displayName: 'Tidal', qualityOptions: const [
          ExtensionQualityOption(id: 'HI_RES_LOSSLESS', label: 'Hi-Res FLAC'),
        ]),
        _fakeSource(id: 'deezer', displayName: 'Deezer'), // no options -> fallback
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
                    result = await showDownloadSheet(context,
                        track: _track, sources: sources);
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

      // Initially Tidal's option is shown, fallback is not.
      expect(find.text('Hi-Res FLAC'), findsOneWidget);
      expect(find.text('MP3'), findsNothing);

      // Switch to Deezer (no declared options) -> fallback list appears.
      await tester.tap(find.text('Deezer'));
      await tester.pumpAndSettle();
      expect(find.text('Hi-Res FLAC'), findsNothing);
      expect(find.text('MP3'), findsOneWidget);

      // Download uses the reset selection (fallback's first option).
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(result!.sourceId, 'deezer');
      expect(result!.quality, 'hires');
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

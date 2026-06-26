import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/search_provider.dart'
    as sp show searchProvider, SearchNotifier;
import 'package:lossless_music_download/screens/search_screen.dart';
import 'package:lossless_music_download/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Fake SearchNotifier that returns a fixed state without I/O
// ---------------------------------------------------------------------------
class _FakeSearchNotifier extends sp.SearchNotifier {
  final List<Track> _tracks;
  _FakeSearchNotifier(this._tracks);

  @override
  List<Track> build() => _tracks;
}

// ---------------------------------------------------------------------------
// Fake ExtensionsController that returns a fixed list without I/O
// ---------------------------------------------------------------------------
class _FakeExtensionsController extends ExtensionsController {
  final List<InstalledExtension> _list;
  _FakeExtensionsController(this._list);

  @override
  Future<List<InstalledExtension>> build() async => _list;
}

// ---------------------------------------------------------------------------
// Helper: build a minimal InstalledExtension for testing
// ---------------------------------------------------------------------------
InstalledExtension _fakeExt({
  required String id,
  bool enabled = true,
}) =>
    InstalledExtension(
      id: id,
      name: id,
      displayName: id,
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

// ---------------------------------------------------------------------------
// Helper: pump SearchScreen with given provider overrides
// ---------------------------------------------------------------------------
Future<void> pumpSearchScreen(
  WidgetTester tester, {
  required List<Track> tracks,
  required List<InstalledExtension> extensions,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sp.searchProvider
            .overrideWith(() => _FakeSearchNotifier(tracks)),
        extensionsProvider
            .overrideWith(() => _FakeExtensionsController(extensions)),
      ],
      child: MaterialApp(
        theme: appTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const SearchScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  group('SearchScreen', () {
    testWidgets(
        'shows track name and download icon when results are loaded',
        (tester) async {
      await pumpSearchScreen(
        tester,
        tracks: const [Track(id: '1', name: 'Song', artists: 'A')],
        extensions: [_fakeExt(id: 'source1')],
      );

      expect(find.text('Song'), findsOneWidget);
      expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    });

    testWidgets(
        'shows searchNoSources when results empty and no enabled extensions',
        (tester) async {
      await pumpSearchScreen(
        tester,
        tracks: const [],
        extensions: [],
      );

      expect(
        find.text('No sources yet. Install one in Discover.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'shows searchEmpty when results empty and at least one enabled extension',
        (tester) async {
      await pumpSearchScreen(
        tester,
        tracks: const [],
        extensions: [_fakeExt(id: 'source1')],
      );

      expect(find.text('No results.'), findsOneWidget);
    });
  });
}

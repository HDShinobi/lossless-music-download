import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/home_feed.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/models/search_entities.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/home_feed_provider.dart';
import 'package:lossless_music_download/providers/search_provider.dart';
import 'package:lossless_music_download/screens/search_screen.dart';
import 'package:lossless_music_download/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Fake HomeFeedController — returns a fixed list without network I/O.
// ---------------------------------------------------------------------------
class _FakeHomeFeedController extends HomeFeedController {
  final List<HomeFeedSection> _sections;
  _FakeHomeFeedController(this._sections);

  @override
  Future<List<HomeFeedSection>> build() async => _sections;
}

// ---------------------------------------------------------------------------
// Fake ExtensionsController — returns a fixed installed list.
// ---------------------------------------------------------------------------
class _FakeExtensionsController extends ExtensionsController {
  final List<InstalledExtension> _list;
  _FakeExtensionsController(this._list);

  @override
  Future<List<InstalledExtension>> build() async => _list;
}

// ---------------------------------------------------------------------------
// Fake SearchNotifier — used to observe/serve the search-results path.
// ---------------------------------------------------------------------------
class _FakeSearchNotifier extends SearchNotifier {
  final List<Track> _results;
  int searchCalls = 0;
  _FakeSearchNotifier(this._results);

  @override
  SearchResults build() => SearchResults.empty;

  @override
  Future<void> search(String q) async {
    searchCalls++;
    final query = q.trim();
    state = AsyncData(
      query.isEmpty ? SearchResults.empty : SearchResults(tracks: _results),
    );
  }
}

const _homeFeedExt = InstalledExtension(
  id: 'ext-feed',
  name: 'ext-feed',
  displayName: 'Feed Extension',
  version: '1.0.0',
  description: '',
  status: 'active',
  enabled: true,
  types: [],
  permissions: [],
  hasMetadataProvider: false,
  hasDownloadProvider: false,
  hasLyricsProvider: false,
  capabilities: {'homeFeed': true},
);

const _feedTrackItem = HomeFeedItem(
  id: 'track-1',
  type: 'track',
  name: 'Feed Track One',
  artists: 'Feed Artist',
  providerId: 'ext-feed',
);

Future<void> _pumpSearchScreen(
  WidgetTester tester, {
  List<HomeFeedSection> feedSections = const [],
  List<Track> searchResults = const [],
  List<InstalledExtension> extensions = const [_homeFeedExt],
  _FakeSearchNotifier? fakeSearchNotifier,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        extensionsProvider.overrideWith(() => _FakeExtensionsController(extensions)),
        homeFeedControllerProvider
            .overrideWith(() => _FakeHomeFeedController(feedSections)),
        searchProvider.overrideWith(
            () => fakeSearchNotifier ?? _FakeSearchNotifier(searchResults)),
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

void main() {
  group('SearchScreen home feed', () {
    testWidgets(
        'empty query renders feed section title and item name',
        (tester) async {
      await _pumpSearchScreen(
        tester,
        feedSections: const [
          HomeFeedSection(title: 'New releases', items: [_feedTrackItem]),
        ],
      );

      expect(find.text('New releases'), findsOneWidget);
      expect(find.text('Feed Track One'), findsOneWidget);
    });

    testWidgets(
        'typing a query hides the feed immediately (gate reacts to '
        'onChanged) even before the query is submitted', (tester) async {
      final fakeSearch = _FakeSearchNotifier(const []);
      await _pumpSearchScreen(
        tester,
        feedSections: const [
          HomeFeedSection(title: 'New releases', items: [_feedTrackItem]),
        ],
        fakeSearchNotifier: fakeSearch,
      );

      await tester.enterText(find.byType(TextField), 'query');
      await tester.pumpAndSettle();

      // Gate flips as soon as the field is non-empty...
      expect(find.text('New releases'), findsNothing);
      expect(find.text('Feed Track One'), findsNothing);
      // ...but onChanged alone must not have triggered a search (which would
      // pollute persisted recent searches on every keystroke).
      expect(fakeSearch.searchCalls, 0);
    });

    testWidgets(
        'submitting a query calls search exactly once and shows results',
        (tester) async {
      const resultTrack = Track(id: 'r1', name: 'Result Song', artists: 'X');
      final fakeSearch = _FakeSearchNotifier(const [resultTrack]);
      await _pumpSearchScreen(
        tester,
        feedSections: const [
          HomeFeedSection(title: 'New releases', items: [_feedTrackItem]),
        ],
        fakeSearchNotifier: fakeSearch,
      );

      await tester.enterText(find.byType(TextField), 'query');
      await tester.pumpAndSettle();
      expect(fakeSearch.searchCalls, 0);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(fakeSearch.searchCalls, 1);
      expect(find.text('New releases'), findsNothing);
      expect(find.text('Feed Track One'), findsNothing);
      expect(find.text('Result Song'), findsOneWidget);
    });
  });
}

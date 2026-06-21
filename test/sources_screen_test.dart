import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/models/store_extension.dart';
import 'package:lossless_music_download/providers/discover_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/priority_provider.dart';
import 'package:lossless_music_download/screens/sources_screen.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';

// ---------------------------------------------------------------------------
// Fake bridge used by bridge + dirs overrides (avoids MethodChannel calls)
// ---------------------------------------------------------------------------
class _FakeBridge extends BackendBridge {
  final List<InstalledExtension> _list;
  _FakeBridge(this._list);

  @override
  Future<void> initExtensionSystem(String ext, String data) async {}

  @override
  Future<List<InstalledExtension>> getInstalledExtensions() async => _list;

  @override
  Future<void> setExtensionEnabled(String id, bool enabled) async {}

  @override
  Future<void> removeExtension(String id) async {}
}

// ---------------------------------------------------------------------------
// Helper: an InstalledExtension for testing
// ---------------------------------------------------------------------------
InstalledExtension _fakeExt({
  required String id,
  required String displayName,
  bool enabled = true,
  String status = 'active',
  List<String> types = const ['metadata'],
  List<String> permissions = const [],
}) =>
    InstalledExtension(
      id: id,
      name: id,
      displayName: displayName,
      version: '1.2.3',
      description: 'A fake extension',
      status: status,
      enabled: enabled,
      types: types,
      permissions: permissions,
      hasMetadataProvider: true,
      hasDownloadProvider: false,
      hasLyricsProvider: false,
    );

// ---------------------------------------------------------------------------
// Fake DiscoverController that returns a fixed list without network calls.
// ---------------------------------------------------------------------------
class _FakeDiscoverController extends DiscoverController {
  final List<StoreExtension> _list;
  _FakeDiscoverController(this._list);

  @override
  Future<List<StoreExtension>> build() async => _list;
}

// ---------------------------------------------------------------------------
// Helper: pump SourcesScreen with provided extension list
// ---------------------------------------------------------------------------
Future<void> pumpSourcesScreen(
  WidgetTester tester,
  List<InstalledExtension> exts, {
  List<StoreExtension> catalogExts = const [],
}) async {
  final fake = _FakeBridge(exts);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendBridgeProvider.overrideWithValue(fake),
        appDirsProvider.overrideWithValue(
          Future.value(('/fake/ext', '/fake/data')),
        ),
        discoverProvider.overrideWith(() => _FakeDiscoverController(catalogExts)),
        aggregatorUrlProvider.overrideWith(() => _FakeAggregatorUrlNotifier()),
        priorityProvider.overrideWith(() => _FakePriorityController()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const SourcesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeAggregatorUrlNotifier extends AggregatorUrlNotifier {
  @override
  String build() => 'https://example.com/repos.json';

  @override
  Future<void> load() async {}
}

// ---------------------------------------------------------------------------
// Fake PriorityController that returns an empty state without any I/O.
// ---------------------------------------------------------------------------
class _FakePriorityController extends PriorityController {
  @override
  Future<PriorityState> build() async => const PriorityState([], []);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  group('SourcesScreen', () {
    testWidgets(
        'shows extension displayName and a Switch when data is loaded',
        (tester) async {
      await pumpSourcesScreen(
        tester,
        [_fakeExt(id: 'deezer', displayName: 'Deezer')],
      );

      // Should show the displayName
      expect(find.text('Deezer'), findsWidgets);

      // Should show a Switch
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets(
        'shows noExtensions text when data list is empty',
        (tester) async {
      await pumpSourcesScreen(tester, []);

      // Should show no-extensions text (en locale)
      expect(
        find.text('No sources yet. Add one in Discover.'),
        findsOneWidget,
      );

      // No Switch when empty
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets(
        'shows DiscoverTab empty state when Discover segment is tapped',
        (tester) async {
      await pumpSourcesScreen(tester, [], catalogExts: []);

      // Tap Discover segment
      await tester.tap(find.text('Discover'));
      await tester.pumpAndSettle();

      // DiscoverTab is now shown — no "Coming soon" for Discover
      expect(
        find.text('No extensions yet. Check the aggregator source.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'shows PriorityTab when Priority segment is tapped',
        (tester) async {
      await pumpSourcesScreen(tester, []);

      // Tap Priority segment
      await tester.tap(find.text('Priority'));
      await tester.pumpAndSettle();

      // PriorityTab renders group headers (en locale)
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Metadata'), findsOneWidget);
    });
  });
}

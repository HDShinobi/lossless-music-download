import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/models/store_extension.dart';
import 'package:lossless_music_download/providers/discover_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:lossless_music_download/widgets/discover_tab.dart';

// ---------------------------------------------------------------------------
// Fake DiscoverController — returns a fixed list without network I/O.
// ---------------------------------------------------------------------------
class _FakeDiscoverController extends DiscoverController {
  final List<StoreExtension> _list;
  _FakeDiscoverController(this._list);

  @override
  Future<List<StoreExtension>> build() async => _list;
}

// ---------------------------------------------------------------------------
// Fake AggregatorUrlNotifier — returns a fixed URL without SharedPreferences.
// ---------------------------------------------------------------------------
class _FakeAggregatorUrlNotifier extends AggregatorUrlNotifier {
  final String _url;
  _FakeAggregatorUrlNotifier([this._url = 'https://example.com/repos.json']);

  @override
  String build() => _url;

  @override
  Future<void> load() async {}
}

// ---------------------------------------------------------------------------
// Fake BackendBridge — no MethodChannel calls.
// ---------------------------------------------------------------------------
class _FakeBridge extends BackendBridge {
  @override
  Future<void> initExtensionSystem(String ext, String data) async {}

  @override
  Future<List<InstalledExtension>> getInstalledExtensions() async => [];
}

// ---------------------------------------------------------------------------
// Helper — creates a StoreExtension with sensible defaults.
// ---------------------------------------------------------------------------
StoreExtension _fakeStoreExt({
  String id = 'test-ext',
  String displayName = 'Test Extension',
  String category = 'metadata',
  String version = '1.0.0',
}) =>
    StoreExtension(
      id: id,
      displayName: displayName,
      version: version,
      description: 'A fake store extension',
      category: category,
      downloadUrl: 'https://example.com/test-ext.zip',
      sourceName: 'test-registry',
    );

// ---------------------------------------------------------------------------
// Helper — pumps DiscoverTab inside ProviderScope + MaterialApp (en).
// ---------------------------------------------------------------------------
Future<void> pumpDiscoverTab(
  WidgetTester tester, {
  required List<StoreExtension> catalog,
  List<InstalledExtension> installed = const [],
}) async {
  final fakeBridge = _FakeBridge();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Discover catalog
        discoverProvider.overrideWith(() => _FakeDiscoverController(catalog)),
        // Aggregator URL
        aggregatorUrlProvider.overrideWith(
          () => _FakeAggregatorUrlNotifier('https://example.com/repos.json'),
        ),
        // Installed extensions — empty list (no MethodChannel calls)
        backendBridgeProvider.overrideWithValue(fakeBridge),
        appDirsProvider.overrideWithValue(
          Future.value(('/fake/ext', '/fake/data')),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: Scaffold(body: DiscoverTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  group('DiscoverTab', () {
    testWidgets(
      'shows catalog item displayName and Install button when data is loaded',
      (tester) async {
        await pumpDiscoverTab(
          tester,
          catalog: [_fakeStoreExt(displayName: 'Awesome Plugin')],
        );

        // The extension's display name should be visible.
        expect(find.text('Awesome Plugin'), findsOneWidget);

        // An "Install" button should appear (en locale).
        expect(find.text('Install'), findsOneWidget);
      },
    );

    testWidgets(
      'shows empty-state text when catalog data is empty',
      (tester) async {
        await pumpDiscoverTab(tester, catalog: []);

        // en value of discoverEmpty
        expect(
          find.text('No extensions yet. Check the aggregator source.'),
          findsOneWidget,
        );
      },
    );
  });
}

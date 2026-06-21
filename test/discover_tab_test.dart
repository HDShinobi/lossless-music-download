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
// Fake DiscoverController — always throws (simulates AsyncError).
// ---------------------------------------------------------------------------
class _ErrorDiscoverController extends DiscoverController {
  @override
  Future<List<StoreExtension>> build() async =>
      throw Exception('network error');
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
        // Optionally override installed extensions list directly
        extensionsProvider.overrideWith(
          () => _FakeExtensionsController(installed),
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
// Helper — pumps DiscoverTab with error state from discoverProvider.
// ---------------------------------------------------------------------------
Future<void> pumpDiscoverTabError(WidgetTester tester) async {
  final fakeBridge = _FakeBridge();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        discoverProvider.overrideWith(() => _ErrorDiscoverController()),
        aggregatorUrlProvider.overrideWith(
          () => _FakeAggregatorUrlNotifier('https://example.com/repos.json'),
        ),
        backendBridgeProvider.overrideWithValue(fakeBridge),
        appDirsProvider.overrideWithValue(
          Future.value(('/fake/ext', '/fake/data')),
        ),
        extensionsProvider.overrideWith(
          () => _FakeExtensionsController(const []),
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
// Fake ExtensionsController — returns a fixed installed list.
// ---------------------------------------------------------------------------
class _FakeExtensionsController extends ExtensionsController {
  final List<InstalledExtension> _list;
  _FakeExtensionsController(this._list);

  @override
  Future<List<InstalledExtension>> build() async => _list;
}

InstalledExtension _fakeInstalledExt({
  required String id,
  String displayName = 'Installed Ext',
}) =>
    InstalledExtension(
      id: id,
      name: id,
      version: '1.0.0',
      enabled: true,
      types: const [],
      displayName: displayName,
      description: 'An installed extension',
      status: 'active',
      permissions: const [],
      hasMetadataProvider: false,
      hasDownloadProvider: false,
      hasLyricsProvider: false,
    );

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

    // M5: error state shows discoverError string
    testWidgets(
      'shows discoverError string when discoverProvider is AsyncError',
      (tester) async {
        await pumpDiscoverTabError(tester);

        // en value of discoverError
        expect(
          find.text('Could not load list. Check the source/URL.'),
          findsOneWidget,
        );
      },
    );

    // M5: extension matching installed list shows "Installed" label, no install button
    testWidgets(
      'shows installed label and no tappable install button for installed extension',
      (tester) async {
        const installedId = 'my-ext';

        await pumpDiscoverTab(
          tester,
          catalog: [
            _fakeStoreExt(id: installedId, displayName: 'My Extension'),
          ],
          installed: [_fakeInstalledExt(id: installedId)],
        );

        // "Installed" label (en) should be visible
        expect(find.text('Installed'), findsOneWidget);

        // The install button must NOT be tappable — verify by checking that
        // no enabled TextButton with "Install" text exists.
        final installButtons = tester.widgetList<TextButton>(
          find.widgetWithText(TextButton, 'Install'),
        );
        for (final btn in installButtons) {
          expect(btn.onPressed, isNull,
              reason: 'Install button must be disabled for installed extension');
        }
      },
    );
  });
}

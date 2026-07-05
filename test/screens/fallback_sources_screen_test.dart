import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/screens/fallback_sources_screen.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';

// ---------------------------------------------------------------------------
// Fake extensions — two enabled download-capable sources.
// ---------------------------------------------------------------------------
InstalledExtension _fakeExt({
  required String id,
  required String displayName,
  bool enabled = true,
  bool hasDownloadProvider = true,
}) =>
    InstalledExtension(
      id: id,
      name: id,
      displayName: displayName,
      version: '1.0.0',
      description: '',
      status: 'active',
      enabled: enabled,
      types: const [],
      permissions: const [],
      hasDownloadProvider: hasDownloadProvider,
      hasMetadataProvider: false,
      hasLyricsProvider: false,
    );

final _qobuz = _fakeExt(id: 'qobuz', displayName: 'Qobuz');
final _tidal = _fakeExt(id: 'tidal', displayName: 'Tidal');

class _FakeExtensionsController extends ExtensionsController {
  final List<InstalledExtension> _list;
  _FakeExtensionsController(this._list);

  @override
  Future<List<InstalledExtension>> build() async => _list;
}

// ---------------------------------------------------------------------------
// Fake bridge — records setDownloadFallbackProviderIds calls without hitting
// any real MethodChannel.
// ---------------------------------------------------------------------------
class FallbackFakeBridge extends BackendBridge {
  final List<List<String>> pushed = [];

  @override
  Future<void> setDownloadFallbackProviderIds(List<String> ids) async {
    pushed.add(ids);
  }
}

// ---------------------------------------------------------------------------
// Helper — pumps FallbackSourcesScreen inside ProviderScope + MaterialApp.
// ---------------------------------------------------------------------------
Future<FallbackFakeBridge> pumpFallbackSourcesScreen(
  WidgetTester tester, {
  List<InstalledExtension> installed = const [],
}) async {
  final fakeBridge = FallbackFakeBridge();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendBridgeProvider.overrideWithValue(fakeBridge),
        extensionsProvider.overrideWith(
          () => _FakeExtensionsController(installed),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: FallbackSourcesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fakeBridge;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('FallbackSourcesScreen', () {
    testWidgets('lists enabled download extensions, all checked when pool is null',
        (tester) async {
      await pumpFallbackSourcesScreen(tester, installed: [_qobuz, _tidal]);

      expect(find.text('Qobuz'), findsOneWidget);
      expect(find.text('Tidal'), findsOneWidget);
      // both checked when pool is null (all)
      expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((c) => c.value == true),
        isTrue,
      );
    });

    testWidgets('excludes disabled and non-download extensions', (tester) async {
      final disabled = _fakeExt(id: 'disabled', displayName: 'Disabled', enabled: false);
      final noDownload = _fakeExt(
        id: 'no-download',
        displayName: 'NoDownload',
        hasDownloadProvider: false,
      );
      await pumpFallbackSourcesScreen(
        tester,
        installed: [_qobuz, _tidal, disabled, noDownload],
      );

      expect(find.text('Disabled'), findsNothing);
      expect(find.text('NoDownload'), findsNothing);
    });

    testWidgets('unchecking one source persists an explicit list of the rest',
        (tester) async {
      final bridge = await pumpFallbackSourcesScreen(
        tester,
        installed: [_qobuz, _tidal],
      );

      await tester.tap(find.widgetWithText(CheckboxListTile, 'Qobuz'));
      await tester.pumpAndSettle();

      // Now only Tidal should be checked.
      final tiles = tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(
        tiles.firstWhere((c) => (c.title as Text).data == 'Qobuz').value,
        isFalse,
      );
      expect(
        tiles.firstWhere((c) => (c.title as Text).data == 'Tidal').value,
        isTrue,
      );

      // Persisted as an explicit pool containing only tidal.
      expect(bridge.pushed.last, ['tidal']);
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString('download_fallback_provider_ids')!),
        ['tidal'],
      );
    });
  });
}

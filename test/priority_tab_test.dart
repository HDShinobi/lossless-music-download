import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/providers/priority_provider.dart';
import 'package:lossless_music_download/widgets/priority_tab.dart';

// ---------------------------------------------------------------------------
// Fake extensions
// ---------------------------------------------------------------------------
InstalledExtension _fakeExt({
  required String id,
  required String displayName,
  bool hasDownload = false,
  bool hasMetadata = false,
}) =>
    InstalledExtension(
      id: id,
      name: id,
      displayName: displayName,
      version: '1.0.0',
      description: '',
      status: 'active',
      enabled: true,
      types: const [],
      permissions: const [],
      hasDownloadProvider: hasDownload,
      hasMetadataProvider: hasMetadata,
      hasLyricsProvider: false,
    );

final _extA = _fakeExt(
  id: 'ext-a',
  displayName: 'Extension Alpha',
  hasDownload: true,
);
final _extB = _fakeExt(
  id: 'ext-b',
  displayName: 'Extension Beta',
  hasDownload: true,
);
final _extC = _fakeExt(
  id: 'ext-c',
  displayName: 'Extension Gamma',
  hasMetadata: true,
);

// ---------------------------------------------------------------------------
// Fake PriorityController — returns fixed state without any async I/O.
// ---------------------------------------------------------------------------
class _FakePriorityController extends PriorityController {
  final List<InstalledExtension> _download;
  final List<InstalledExtension> _metadata;

  _FakePriorityController({
    required List<InstalledExtension> download,
    required List<InstalledExtension> metadata,
  })  : _download = download,
        _metadata = metadata;

  @override
  Future<PriorityState> build() async => PriorityState(_download, _metadata);
}

// ---------------------------------------------------------------------------
// Helper — pumps PriorityTab inside ProviderScope + MaterialApp (en).
// ---------------------------------------------------------------------------
Future<void> pumpPriorityTab(
  WidgetTester tester, {
  required List<InstalledExtension> download,
  required List<InstalledExtension> metadata,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        priorityProvider.overrideWith(
          () => _FakePriorityController(
            download: download,
            metadata: metadata,
          ),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: Scaffold(body: PriorityTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  group('PriorityTab', () {
    testWidgets(
      'shows group headers, extension names, and ReorderableListView when data is loaded',
      (tester) async {
        await pumpPriorityTab(
          tester,
          download: [_extA, _extB],
          metadata: [_extC],
        );

        // Group labels (en locale)
        expect(find.text('Download'), findsOneWidget);
        expect(find.text('Metadata'), findsOneWidget);

        // Extension display names
        expect(find.text('Extension Alpha'), findsOneWidget);
        expect(find.text('Extension Beta'), findsOneWidget);
        expect(find.text('Extension Gamma'), findsOneWidget);

        // At least one ReorderableListView should be present
        expect(find.byType(ReorderableListView), findsWidgets);
      },
    );

    testWidgets(
      'shows empty-state text for both groups when lists are empty',
      (tester) async {
        await pumpPriorityTab(
          tester,
          download: [],
          metadata: [],
        );

        // Both groups show the empty-state string (en locale)
        expect(
          find.text('No sources for this group yet.'),
          findsWidgets,
        );

        // No ReorderableListView when both lists are empty
        expect(find.byType(ReorderableListView), findsNothing);
      },
    );
  });
}

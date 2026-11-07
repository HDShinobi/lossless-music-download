import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/screens/lyrics_settings_screen.dart';

class _Extensions extends ExtensionsController {
  @override
  Future<List<InstalledExtension>> build() async => [
    for (final item in [
      ('Lyrics', true, true),
      ('Disabled', false, true),
      ('Audio', true, false),
    ])
      InstalledExtension.fromJson({
        'id': item.$1,
        'name': item.$1,
        'enabled': item.$2,
        'has_lyrics_provider': item.$3,
      }),
  ];
}

void main() {
  final calls = <MethodCall>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.losslessmusic/native'),
          (call) async {
            calls.add(call);
            return null;
          },
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.losslessmusic/native'),
          null,
        ),
  );

  Future<void> showPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [extensionsProvider.overrideWith(_Extensions.new)],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LyricsSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'reorder and disable persist and apply; only lyrics extensions appear',
    (tester) async {
      await showPage(tester);
      expect(find.byKey(const ValueKey('extension:disabled')), findsNothing);
      expect(find.byKey(const ValueKey('extension:audio')), findsNothing);
      final reorder = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      reorder.onReorder(0, 2);
      await tester.pumpAndSettle();
      expect(jsonDecode((calls.last.arguments as Map)['providers_json']), [
        'lrcred',
        'apple_music',
        'mornye_lyrics',
        'lyricsplus',
        'lrclib',
      ]);
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('apple_music')))
          .onChanged!(false);
      await tester.pumpAndSettle();
      expect(jsonDecode((calls.last.arguments as Map)['providers_json']), [
        'lrcred',
        'mornye_lyrics',
        'lyricsplus',
        'lrclib',
      ]);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('extension:lyrics')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('extension:lyrics')),
          )
          .onChanged!(true);
      await tester.pumpAndSettle();
      expect(
        jsonDecode((calls.last.arguments as Map)['providers_json']).last,
        'extension:lyrics',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('lyrics_providers'),
        (calls.last.arguments as Map)['providers_json'],
      );
    },
  );

  testWidgets('save mode changes the existing download flags', (tester) async {
    await showPage(tester);
    tester
        .widget<DropdownButton<String>>(
          find.byKey(const ValueKey('lyricsSaveMode')),
        )
        .onChanged!('both');
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('embed_lyrics'), true);
    expect(prefs.getBool('write_lrc_sidecar'), true);
  });

  testWidgets('language has an explicit save action', (tester) async {
    await showPage(tester);
    await tester.scrollUntilVisible(
      find.byType(TextFormField),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextFormField), 'VI');
    expect(find.text('Save'), findsOneWidget);
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(jsonDecode((calls.last.arguments as Map)['options_json']), {
      'musixmatch_language': 'vi',
    });
  });

  for (final mode in [
    (true, false, 'embed'),
    (false, true, 'external'),
    (true, true, 'both'),
    (false, false, 'off'),
  ]) {
    testWidgets('preserves legacy save mode ${mode.$3}', (tester) async {
      SharedPreferences.setMockInitialValues({
        'embed_lyrics': mode.$1,
        'write_lrc_sidecar': mode.$2,
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [extensionsProvider.overrideWith(_Extensions.new)],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LyricsSettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dropdown = tester.widget<DropdownButton<String>>(
        find.byKey(const ValueKey('lyricsSaveMode')),
      );
      expect(dropdown.value, mode.$3);
      expect(find.text('Apple Music'), findsOneWidget);
      expect(find.text('lrc.red'), findsOneWidget);
    });
  }
}

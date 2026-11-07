import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/providers/download_options_provider.dart';
import 'package:lossless_music_download/screens/download_file_settings_screen.dart';

void main() {
  testWidgets('template editor previews drafts and never saves invalid input', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const DownloadFileSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filename template'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '{unknown}');
    await tester.pump();
    expect(find.textContaining('Use supported placeholders'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(c.read(filenameTemplateProvider), '');
    await tester.enterText(find.byType(TextField), '{track}. {title}');
    await tester.pump();
    expect(find.textContaining('03. Sample Song.flac'), findsWidgets);
    expect(find.textContaining('2-03. Sample Song.flac'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.read(filenameTemplateProvider), '{track}. {title}');
    expect(tester.takeException(), isNull);
  });
}

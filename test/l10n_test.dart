import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';

Widget _wrap(Locale l) => MaterialApp(
      locale: l,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (c) => Text(AppLocalizations.of(c).tabSearch)),
    );

void main() {
  testWidgets('vi shows Tìm', (t) async {
    await t.pumpWidget(_wrap(const Locale('vi')));
    await t.pumpAndSettle();
    expect(find.text('Tìm'), findsOneWidget);
  });
  testWidgets('en shows Search', (t) async {
    await t.pumpWidget(_wrap(const Locale('en')));
    await t.pumpAndSettle();
    expect(find.text('Search'), findsOneWidget);
  });
}

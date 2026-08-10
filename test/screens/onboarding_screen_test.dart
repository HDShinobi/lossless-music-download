import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/screens/onboarding_screen.dart';

Widget _wrap() => ProviderScope(
      child: MaterialApp(
        locale: const Locale('vi'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const OnboardingScreen(),
      ),
    );

void main() {
  testWidgets('welcome page shows app name, both languages and Next', (t) async {
    await t.pumpWidget(_wrap());
    await t.pump(); // flush the initState permission-state setState

    expect(find.text('Lossless Music'), findsOneWidget);
    expect(find.text('Tiếng Việt'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Tiếp'), findsOneWidget); // primary "Next"
    // Back button is hidden on the first page.
    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });
}

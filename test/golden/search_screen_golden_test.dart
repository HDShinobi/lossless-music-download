import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/screens/search_screen.dart';

void main() {
  goldenTest(
    'SearchScreen renders',
    fileName: 'search_screen',
    builder: () => GoldenTestGroup(
      children: [
        GoldenTestScenario(
          name: 'vi',
          constraints: const BoxConstraints.tightFor(width: 390, height: 844),
          child: MaterialApp(
            locale: const Locale('vi'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const SearchScreen(),
          ),
        ),
      ],
    ),
  );
}

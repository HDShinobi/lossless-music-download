import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/screens/search_screen.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';

class _EmptyBridge extends BackendBridge {
  @override
  Future<void> initExtensionSystem(String ext, String data) async {}

  @override
  Future<List<InstalledExtension>> getInstalledExtensions() async => [];
}

Widget _wrap(Locale locale) => ProviderScope(
      overrides: [
        backendBridgeProvider.overrideWithValue(_EmptyBridge()),
        appDirsProvider.overrideWithValue(
          Future.value(('/fake/ext', '/fake/data')),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const SearchScreen(),
      ),
    );

void main() {
  goldenTest(
    'SearchScreen renders',
    fileName: 'search_screen',
    builder: () => GoldenTestGroup(
      children: [
        GoldenTestScenario(
          name: 'vi',
          constraints: const BoxConstraints.tightFor(width: 390, height: 844),
          child: _wrap(const Locale('vi')),
        ),
        GoldenTestScenario(
          name: 'en',
          constraints: const BoxConstraints.tightFor(width: 390, height: 844),
          child: _wrap(const Locale('en')),
        ),
      ],
    ),
  );
}

import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/screens/search_screen.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:lossless_music_download/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyBridge extends BackendBridge {
  @override
  Future<void> initExtensionSystem(String ext, String data) async {}

  @override
  Future<String?> loadExtensionsFromDir(String dirPath) async => null;

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
        theme: appTheme(),
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const SearchScreen(),
      ),
    );

void main() {
  // homeFeedControllerProvider's source setting reads SharedPreferences on
  // build (via a background microtask); mock it so that read succeeds
  // instead of throwing MissingPluginException while empty-query search
  // now renders the home feed (or its empty state) by default.
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

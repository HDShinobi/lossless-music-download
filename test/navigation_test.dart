import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lossless_music_download/main.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/screens/fallback_sources_screen.dart';
import 'package:lossless_music_download/screens/library_screen.dart';
import 'package:lossless_music_download/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Empty-query search (the default tab) now renders homeFeedControllerProvider,
// which awaits extensionsProvider.future. Override it so that future resolves
// instantly instead of hitting the real (unmocked) native extension bridge.
class _FakeExtensionsController extends ExtensionsController {
  @override
  Future<List<InstalledExtension>> build() async => const [];
}

void main() {
  // The Library screen awaits downloadDirProvider, which reads SharedPreferences
  // to resolve the (possibly user-chosen) download folder. Seed the in-memory
  // store so getInstance() completes instead of hanging pumpAndSettle.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tapping Library tab shows Library screen', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        extensionsProvider.overrideWith(() => _FakeExtensionsController()),
      ],
      child: const MyApp(),
    ));
    await t.pumpAndSettle();
    expect(find.text('Tìm'), findsWidgets); // default vi, Search tab
    await t.tap(find.text('Thư viện'));
    await t.pumpAndSettle();
    expect(find.text('Thư viện'), findsWidgets);
    expect(find.byType(LibraryScreen), findsOneWidget);
  });

  // Guards the invariant that a Settings sub-page always leaves Settings
  // beneath it, so system-back returns instead of closing the app. Note this
  // passes with both context.go() and context.push(), so it does not by itself
  // explain the on-device report of back exiting the app.
  testWidgets('back from a Settings sub-page returns to Settings', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        extensionsProvider.overrideWith(() => _FakeExtensionsController()),
      ],
      child: const MyApp(),
    ));
    await t.pumpAndSettle();

    await t.tap(find.text('Cài đặt'));
    await t.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    await t.tap(find.text('Nguồn dự phòng'));
    await t.pumpAndSettle();
    expect(find.byType(FallbackSourcesScreen), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);

    // didPopRoute() is what the Android back gesture triggers. It must be
    // handled (true) rather than bubbling up to close the app (false).
    final popped = await t.binding.handlePopRoute();
    await t.pumpAndSettle();

    expect(popped, isTrue, reason: 'back must be consumed, not exit the app');
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(FallbackSourcesScreen), findsNothing);
  });

}

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lossless_music_download/main.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/screens/library_screen.dart';
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
}

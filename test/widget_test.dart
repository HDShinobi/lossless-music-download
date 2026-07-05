// Basic widget test – kept as a sanity check that the app tree inflates.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lossless_music_download/main.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Empty-query search (the default tab) now renders homeFeedControllerProvider,
// which awaits extensionsProvider.future. Override it so that future resolves
// instantly instead of hitting the real (unmocked) native extension bridge.
class _FakeExtensionsController extends ExtensionsController {
  @override
  Future<List<InstalledExtension>> build() async => const [];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('app inflates without errors', (WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        extensionsProvider.overrideWith(() => _FakeExtensionsController()),
      ],
      child: const MyApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

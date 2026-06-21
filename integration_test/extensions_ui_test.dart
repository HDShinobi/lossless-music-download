import 'dart:io';
import 'dart:convert';
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';

// Integration test: an installed synthetic extension surfaces through
// extensionsProvider (AsyncNotifier) on a real device.
//
// The synthetic .spotiflac-ext recipe is identical to the one proven in
// extension_engine_test.dart (Phase 1b):
//   manifest.json — name/displayName/version/description/type/permissions
//   index.js      — registerExtension({})
//
// The test overrides appDirsProvider with temp dirs under
// getApplicationDocumentsDirectory() to keep state isolated from the live app.

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('installed extension surfaces via extensionsProvider',
      (tester) async {
    // ── Temp dirs ────────────────────────────────────────────────────────────
    final docs = await getApplicationDocumentsDirectory();
    final extDir = Directory('${docs.path}/ui_test_ext');
    final dataDir = Directory('${docs.path}/ui_test_data');
    if (extDir.existsSync()) extDir.deleteSync(recursive: true);
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
    extDir.createSync(recursive: true);
    dataDir.createSync(recursive: true);

    // ── Build synthetic .spotiflac-ext ───────────────────────────────────────
    final manifest = jsonEncode({
      'name': 'dummy-ui-test',
      'displayName': 'Dummy UI Test',
      'version': '1.0.0',
      'description': 'Synthetic extension for extensionsProvider integration test',
      'type': ['metadata_provider'],
      'permissions': {
        'network': <String>[],
        'storage': false,
        'file': false,
      },
    });
    const indexJs = 'registerExtension({});';

    final manifestBytes = utf8.encode(manifest);
    final indexJsBytes = utf8.encode(indexJs);
    final archive = Archive()
      ..addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes))
      ..addFile(ArchiveFile('index.js', indexJsBytes.length, indexJsBytes));

    final extPath = '${docs.path}/dummy-ui-test.spotiflac-ext';
    File(extPath).writeAsBytesSync(ZipEncoder().encode(archive)!);

    // ── Pump a minimal app so platform channels are available ────────────────
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    // ── ProviderContainer with appDirsProvider overridden to temp dirs ───────
    final container = ProviderContainer(
      overrides: [
        appDirsProvider.overrideWithValue(
          Future.value((extDir.path, dataDir.path)),
        ),
      ],
    );
    addTearDown(container.dispose);

    // ── Read extensionsProvider — triggers init + initial list ────────────────
    // Wait for the AsyncNotifier to complete building.
    final initialState = await container.read(extensionsProvider.future);
    expect(initialState, isNotNull,
        reason: 'extensionsProvider should resolve without error');

    // ── Install synthetic extension via BackendBridge ─────────────────────────
    final bridge = container.read(backendBridgeProvider);
    await bridge.installExtension(extPath);

    // ── Refresh provider list ─────────────────────────────────────────────────
    await container.read(extensionsProvider.notifier).refresh();

    // Wait for the refresh to settle.
    final refreshedState = await container.read(extensionsProvider.future);

    // ── Assertions ────────────────────────────────────────────────────────────
    expect(
      refreshedState.any(
          (e) => e.id == 'dummy-ui-test' || e.name == 'Dummy UI Test'),
      isTrue,
      reason: 'extensionsProvider list should contain the installed extension',
    );

    final ext = refreshedState.firstWhere(
        (e) => e.id == 'dummy-ui-test' || e.name == 'Dummy UI Test');

    expect(ext.displayName, isNotEmpty,
        reason: 'displayName should be non-empty');

    expect(ext.permissions, isA<List<String>>(),
        reason: 'permissions field should parse to a List<String>');

    // ── Cleanup ───────────────────────────────────────────────────────────────
    await container.read(extensionsProvider.notifier).remove(ext.id);

    final finalState = await container.read(extensionsProvider.future);
    expect(
      finalState.any((e) => e.id == ext.id),
      isFalse,
      reason: 'extension should be gone after remove()',
    );

    // Clean up temp files.
    if (File(extPath).existsSync()) File(extPath).deleteSync();
  });
}

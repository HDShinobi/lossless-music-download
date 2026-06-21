import 'dart:io';
import 'dart:convert';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';

// The synthetic extension manifest satisfies every field validated by
// go_backend/extension_manifest.go:
//   - name, version, description (all non-empty)
//   - type: at least one of the three valid ExtensionType values
//   - no settings/serviceHealth, so no further required sub-fields
//
// The synthetic index.js calls registerExtension({}) so that
// go_backend/extension_manager.go:initializeVMLocked() passes the
// "extension did not call registerExtension()" guard used by
// validateExtensionLoad().

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final bridge = BackendBridge();

  testWidgets('install + list + disable + remove a synthetic extension',
      (tester) async {
    final docs = await getApplicationDocumentsDirectory();

    // Use fresh dirs per run so there is no stale state from a previous run.
    final extDir = Directory('${docs.path}/ext_test_engine');
    if (extDir.existsSync()) extDir.deleteSync(recursive: true);
    extDir.createSync(recursive: true);

    final dataDir = Directory('${docs.path}/ext_data_engine');
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
    dataDir.createSync(recursive: true);

    await bridge.initExtensionSystem(extDir.path, dataDir.path);

    // Manifest fields required by ParseManifest/Validate in extension_manifest.go:
    //   name, version, description (all non-empty strings)
    //   type: non-empty list of valid ExtensionType values
    //   permissions: present (empty network list is fine)
    final manifest = jsonEncode({
      'name': 'dummy-synthetic',
      'displayName': 'Dummy Synthetic',
      'version': '1.0.0',
      'description': 'Minimal synthetic extension for integration testing',
      'type': ['metadata_provider'],
      'permissions': {
        'network': <String>[],
        'storage': false,
        'file': false,
      },
    });

    // index.js must call registerExtension() — the Go runtime sets up a
    // 'registerExtension' global and checks that it was invoked.
    const indexJs = 'registerExtension({});';

    final manifestBytes = utf8.encode(manifest);
    final indexJsBytes = utf8.encode(indexJs);

    final archive = Archive()
      ..addFile(
          ArchiveFile('manifest.json', manifestBytes.length, manifestBytes))
      ..addFile(ArchiveFile('index.js', indexJsBytes.length, indexJsBytes));

    final extPath = '${docs.path}/dummy-synthetic.spotiflac-ext';
    File(extPath).writeAsBytesSync(ZipEncoder().encode(archive)!);

    // ── Install ──────────────────────────────────────────────────────────────
    await bridge.installExtension(extPath);

    // ── List → must contain our extension ───────────────────────────────────
    var list = await bridge.getInstalledExtensions();
    expect(
      list.any((e) => e.id == 'dummy-synthetic' || e.name == 'Dummy Synthetic'),
      isTrue,
      reason: 'installed extension should appear in getInstalledExtensions()',
    );

    final installed =
        list.firstWhere((e) => e.id == 'dummy-synthetic' || e.name == 'Dummy Synthetic');
    final id = installed.id;

    // ── Disable ──────────────────────────────────────────────────────────────
    await bridge.setExtensionEnabled(id, false);

    // ── Remove ───────────────────────────────────────────────────────────────
    await bridge.removeExtension(id);

    // ── List → must no longer contain our extension ──────────────────────────
    list = await bridge.getInstalledExtensions();
    expect(
      list.any((e) => e.id == id),
      isFalse,
      reason: 'removed extension should not appear in getInstalledExtensions()',
    );
  });
}

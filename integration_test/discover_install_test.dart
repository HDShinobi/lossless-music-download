import 'dart:io';
import 'dart:convert';
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lossless_music_download/providers/discover_provider.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';

// Integration test: discover → download → install via a local HTTP server.
//
// A Dart HttpServer runs IN the same test process, serving:
//   /repos.json       aggregator index
//   /registry.json    single-extension catalog
//   /dummy.spotiflac-ext  synthetic ZIP (manifest.json + index.js)
//
// ProviderContainer overrides aggregatorUrlProvider → local server URL and
// appDirsProvider → temp dirs so the test is fully isolated from the live app.
// httpClientProvider and BackendBridge are real.

// ---------------------------------------------------------------------------
// Helper: build a synthetic .spotiflac-ext as raw bytes
// ---------------------------------------------------------------------------
List<int> _buildSyntheticExt() {
  final manifest = jsonEncode({
    'name': 'dummy-store',
    'displayName': 'Dummy Store',
    'version': '1.0.0',
    'description': 'Synthetic extension for discover-install integration test',
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

  return ZipEncoder().encode(archive)!;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('discover → download → install via local HTTP server',
      (tester) async {
    // ── Build the synthetic .ext bytes once ──────────────────────────────────
    final extBytes = _buildSyntheticExt();

    // ── Start in-test HTTP server ────────────────────────────────────────────
    final server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;

    // Serve requests asynchronously (fire-and-forget listener).
    server.listen((req) async {
      final path = req.uri.path;
      HttpResponse res = req.response;
      try {
        if (path == '/repos.json') {
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode({
            'version': 1,
            'repos': [
              {
                'name': 'Test',
                'url': 'http://127.0.0.1:$port/registry.json',
              }
            ],
          }));
        } else if (path == '/registry.json') {
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode({
            'version': 1,
            'extensions': [
              {
                'id': 'dummy-store',
                'display_name': 'Dummy Store',
                'version': '1.0.0',
                'description': 'd',
                'category': 'metadata',
                'download_url':
                    'http://127.0.0.1:$port/dummy.spotiflac-ext',
              }
            ],
          }));
        } else if (path == '/dummy.spotiflac-ext') {
          res.headers
              .set('content-type', 'application/octet-stream');
          res.add(extBytes);
        } else {
          res.statusCode = 404;
        }
      } finally {
        await res.close();
      }
    });

    // ── Temp dirs ────────────────────────────────────────────────────────────
    final docs = await getApplicationDocumentsDirectory();
    final extDir = Directory('${docs.path}/di_test_ext');
    final dataDir = Directory('${docs.path}/di_test_data');
    if (extDir.existsSync()) extDir.deleteSync(recursive: true);
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
    extDir.createSync(recursive: true);
    dataDir.createSync(recursive: true);

    // ── Pump a minimal app so platform channels are live ─────────────────────
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    // ── ProviderContainer with overrides ─────────────────────────────────────
    final container = ProviderContainer(
      overrides: [
        // Point aggregator at our local server.
        aggregatorUrlProvider.overrideWith(
          () => _LocalAggregatorNotifier('http://127.0.0.1:$port/repos.json'),
        ),
        // Isolate extension & data dirs from the live app.
        appDirsProvider.overrideWithValue(
          Future.value((extDir.path, dataDir.path)),
        ),
      ],
    );
    addTearDown(container.dispose);

    // ── 0. Prime extensionsProvider so initExtensionSystem runs with our dirs ─
    // This MUST happen before install(), because installExtension() in Go uses
    // the extDir that was set during initExtensionSystem.
    await container.read(extensionsProvider.future);

    // ── 1. discoverProvider: catalog must contain dummy-store ────────────────
    final catalog = await container.read(discoverProvider.future);
    expect(
      catalog.any((e) => e.id == 'dummy-store'),
      isTrue,
      reason: 'discoverProvider should return dummy-store from local server',
    );

    // ── 2. install ───────────────────────────────────────────────────────────
    final entry = catalog.firstWhere((e) => e.id == 'dummy-store');
    await container.read(discoverProvider.notifier).install(entry);

    // ── 3. extensionsProvider.refresh() → installed list must contain it ─────
    await container.read(extensionsProvider.notifier).refresh();
    final installed = await container.read(extensionsProvider.future);
    expect(
      installed.any((e) => e.id == 'dummy-store'),
      isTrue,
      reason: 'extensionsProvider should list dummy-store after install',
    );

    final ext = installed.firstWhere((e) => e.id == 'dummy-store');
    expect(ext.displayName, isNotEmpty,
        reason: 'displayName should be non-empty');
    expect(ext.permissions, isA<List<String>>(),
        reason: 'permissions field should parse to a List<String>');

    // ── 4. Teardown: remove extension + close server ─────────────────────────
    await container.read(extensionsProvider.notifier).remove('dummy-store');
    await server.close(force: true);

    final finalState = await container.read(extensionsProvider.future);
    expect(
      finalState.any((e) => e.id == 'dummy-store'),
      isFalse,
      reason: 'dummy-store should be gone after remove()',
    );
  });
}

// ---------------------------------------------------------------------------
// Fake AggregatorUrlNotifier that starts with a fixed URL (no SharedPrefs).
// ---------------------------------------------------------------------------
class _LocalAggregatorNotifier extends AggregatorUrlNotifier {
  _LocalAggregatorNotifier(this._url);
  final String _url;

  @override
  String build() => _url;

  @override
  Future<void> load() async {
    state = _url;
  }

  @override
  Future<void> set(String url) async {
    state = url;
  }
}

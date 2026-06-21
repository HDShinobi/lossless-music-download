import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lossless_music_download/models/store_extension.dart';
import 'package:lossless_music_download/services/extension_registry_service.dart';

const _aggregatorUrl = 'https://example.com/repos.json';
const _registry1Url = 'https://registry-a.example.com/registry.json';
const _registry2Url = 'https://registry-b.example.com/registry.json';
const _deadRegistryUrl = 'https://dead.example.com/registry.json';
const _downloadUrl = 'https://cdn.example.com/ext-alpha-1.0.0.spotiflac-ext';

final _aggregatorBody = jsonEncode({
  'version': '1',
  'repos': [
    {'name': 'registry-a', 'url': _registry1Url, 'verified': true},
    {'name': 'dead-registry', 'url': _deadRegistryUrl},
    {'name': 'registry-b', 'url': _registry2Url},
  ],
});

final _registry1Body = jsonEncode({
  'version': '1',
  'extensions': [
    {
      'id': 'ext-alpha',
      'name': 'alpha',
      'display_name': 'Alpha Extension',
      'version': '1.0.0',
      'description': 'Alpha desc',
      'download_url': _downloadUrl,
      'category': 'audio',
      'tags': ['lossless'],
      'min_app_version': '1.0.0',
    },
    {
      'id': 'ext-beta',
      'name': 'beta',
      'display_name': 'Beta Extension',
      'version': '2.0.0',
      'description': 'Beta desc',
      'download_url': 'https://cdn.example.com/ext-beta-2.0.0.spotiflac-ext',
      'category': 'utility',
      'min_app_version': '1.0.0',
    },
  ],
});

// registry-b has a duplicate of ext-alpha (different version) + a new ext-gamma.
// First-wins dedup means registry-a's ext-alpha should survive.
final _registry2Body = jsonEncode({
  'version': '1',
  'extensions': [
    {
      'id': 'ext-alpha',
      'name': 'alpha',
      'display_name': 'Alpha Extension (DUPLICATE)',
      'version': '9.9.9',
      'description': 'Should be ignored',
      'download_url': 'https://cdn.example.com/ext-alpha-9.9.9.spotiflac-ext',
      'category': 'audio',
      'min_app_version': '1.0.0',
    },
    {
      'id': 'ext-gamma',
      'name': 'gamma',
      'display_name': 'Gamma Extension',
      'version': '3.0.0',
      'description': 'Gamma desc',
      'download_url': 'https://cdn.example.com/ext-gamma-3.0.0.spotiflac-ext',
      'category': 'utility',
      'icon_url': 'https://cdn.example.com/gamma.png',
      'min_app_version': '1.0.0',
    },
  ],
});

const _fakeExtBytes = [0xDE, 0xAD, 0xBE, 0xEF];

MockClient _buildMockClient() {
  return MockClient((request) async {
    final path = request.url.toString();
    if (path == _aggregatorUrl) {
      return http.Response(_aggregatorBody, 200);
    }
    if (path == _registry1Url) {
      return http.Response(_registry1Body, 200);
    }
    if (path == _registry2Url) {
      return http.Response(_registry2Body, 200);
    }
    if (path == _deadRegistryUrl) {
      return http.Response('Not Found', 404);
    }
    if (path == _downloadUrl) {
      return http.Response.bytes(_fakeExtBytes, 200);
    }
    return http.Response('Not Found', 404);
  });
}

void main() {
  group('ExtensionRegistryService', () {
    late ExtensionRegistryService svc;

    setUp(() {
      svc = ExtensionRegistryService(_buildMockClient());
    });

    test('fetchCatalog merges extensions from all live registries', () async {
      final catalog = await svc.fetchCatalog(_aggregatorUrl);
      final ids = catalog.map((e) => e.id).toSet();
      // ext-alpha (registry-a), ext-beta (registry-a), ext-gamma (registry-b)
      expect(ids, containsAll(['ext-alpha', 'ext-beta', 'ext-gamma']));
      expect(catalog.length, 3);
    });

    test('fetchCatalog deduplicates by id (first-wins from registry-a)', () async {
      final catalog = await svc.fetchCatalog(_aggregatorUrl);
      final alpha = catalog.firstWhere((e) => e.id == 'ext-alpha');
      // registry-a has version 1.0.0; registry-b duplicate has 9.9.9 and should be ignored
      expect(alpha.version, '1.0.0');
      expect(alpha.displayName, 'Alpha Extension');
      expect(alpha.sourceName, 'registry-a');
    });

    test('fetchCatalog skips dead (404) registry but loads others', () async {
      final catalog = await svc.fetchCatalog(_aggregatorUrl);
      // dead-registry returned 404 — its extensions are absent but registry-a & b still loaded
      expect(catalog.length, 3);
    });

    test('fetchCatalog maps optional icon_url correctly', () async {
      final catalog = await svc.fetchCatalog(_aggregatorUrl);
      final gamma = catalog.firstWhere((e) => e.id == 'ext-gamma');
      expect(gamma.iconUrl, 'https://cdn.example.com/gamma.png');

      final alpha = catalog.firstWhere((e) => e.id == 'ext-alpha');
      expect(alpha.iconUrl, isNull);
    });

    test('downloadExtension writes bytes to destDir/<id>.spotiflac-ext', () async {
      final tempDir = Directory.systemTemp.createTempSync('ext_registry_test_');
      try {
        final catalog = await svc.fetchCatalog(_aggregatorUrl);
        final alpha = catalog.firstWhere((e) => e.id == 'ext-alpha');

        final path = await svc.downloadExtension(alpha, tempDir.path);

        expect(path, endsWith('ext-alpha.spotiflac-ext'));
        final file = File(path);
        expect(file.existsSync(), isTrue);
        expect(file.readAsBytesSync(), equals(_fakeExtBytes));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('downloadExtension with path-traversal id writes inside destDir', () async {
      // Build an extension whose id contains path-traversal sequences.
      final evilExt = StoreExtension(
        id: '../../evil',
        displayName: 'Evil',
        version: '1.0.0',
        description: 'path traversal test',
        category: 'audio',
        downloadUrl: _downloadUrl,
        sourceName: 'test',
      );

      final tempDir = Directory.systemTemp.createTempSync('ext_registry_traversal_');
      try {
        final path = await svc.downloadExtension(evilExt, tempDir.path);

        // The written file must live inside tempDir.
        final resolvedFile = File(path).absolute;
        expect(
          resolvedFile.path,
          startsWith(tempDir.absolute.path),
          reason: 'written path must be inside destDir',
        );

        // The file name must contain the sanitized id (dots and slashes replaced).
        expect(
          resolvedFile.parent.path,
          equals(tempDir.absolute.path),
          reason: 'parent dir must be exactly destDir',
        );
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}

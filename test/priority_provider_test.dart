import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/installed_extension.dart';
import 'package:lossless_music_download/providers/extensions_provider.dart';
import 'package:lossless_music_download/providers/priority_provider.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';

// ---------------------------------------------------------------------------
// Fake bridge — only overrides the priority-related methods.
// ---------------------------------------------------------------------------
class FakePriorityBridge extends BackendBridge {
  final List<String> _downloadPriority;
  final List<String> _metadataPriority;
  final List<List<String>> setDownloadCalls = [];
  final List<List<String>> setMetadataCalls = [];

  FakePriorityBridge({
    List<String> downloadPriority = const [],
    List<String> metadataPriority = const [],
  })  : _downloadPriority = downloadPriority,
        _metadataPriority = metadataPriority;

  @override
  Future<List<String>> getDownloadPriority() async => _downloadPriority;

  @override
  Future<List<String>> getMetadataPriority() async => _metadataPriority;

  @override
  Future<void> setDownloadPriority(List<String> ids) async {
    setDownloadCalls.add(List.unmodifiable(ids));
  }

  @override
  Future<void> setMetadataPriority(List<String> ids) async {
    setMetadataCalls.add(List.unmodifiable(ids));
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
InstalledExtension _ext({
  required String id,
  bool hasDownload = false,
  bool hasMetadata = false,
}) =>
    InstalledExtension(
      id: id,
      name: id,
      displayName: id,
      version: '1.0.0',
      description: '',
      status: 'active',
      enabled: true,
      types: const [],
      permissions: const [],
      hasDownloadProvider: hasDownload,
      hasMetadataProvider: hasMetadata,
      hasLyricsProvider: false,
    );

/// Extensions under test:
///   extA  — download only
///   extB  — download + metadata
///   extC  — metadata only
final _testExts = [
  _ext(id: 'extA', hasDownload: true),
  _ext(id: 'extB', hasDownload: true, hasMetadata: true),
  _ext(id: 'extC', hasMetadata: true),
];

ProviderContainer _makeContainer({
  required FakePriorityBridge bridge,
  List<InstalledExtension>? exts,
}) {
  return ProviderContainer(
    overrides: [
      backendBridgeProvider.overrideWithValue(bridge),
      // Override extensionsProvider so it resolves immediately with our list.
      extensionsProvider.overrideWith(() => _FakeExtController(exts ?? _testExts)),
    ],
  );
}

// Minimal AsyncNotifier that returns a fixed list without touching any channel.
// Must extend ExtensionsController so overrideWith is type-safe.
class _FakeExtController extends ExtensionsController {
  final List<InstalledExtension> _exts;
  _FakeExtController(this._exts);

  @override
  Future<List<InstalledExtension>> build() async => _exts;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  group('priorityProvider — reconcile', () {
    test('download list: saved order first, new candidates appended', () async {
      // savedOrder = ['extB'] → extB comes first, extA appended after
      final bridge = FakePriorityBridge(
        downloadPriority: ['extB'],
        metadataPriority: [],
      );
      final container = _makeContainer(bridge: bridge);
      addTearDown(container.dispose);

      final state = await container.read(priorityProvider.future);

      expect(
        state.download.map((e) => e.id).toList(),
        ['extB', 'extA'],
        reason: 'extB (saved) first, extA (new candidate) appended',
      );
    });

    test('metadata list: unknown saved ids ignored, new candidates appended',
        () async {
      // savedOrder = [] → both extB and extC appended in candidate order
      final bridge = FakePriorityBridge(
        downloadPriority: [],
        metadataPriority: [],
      );
      final container = _makeContainer(bridge: bridge);
      addTearDown(container.dispose);

      final state = await container.read(priorityProvider.future);

      expect(
        state.metadata.map((e) => e.id).toList(),
        containsAll(['extB', 'extC']),
      );
      expect(state.metadata, hasLength(2));
    });

    test('saved id not in candidates is silently dropped', () async {
      final bridge = FakePriorityBridge(
        downloadPriority: ['ghost', 'extA'],
        metadataPriority: [],
      );
      final container = _makeContainer(bridge: bridge);
      addTearDown(container.dispose);

      final state = await container.read(priorityProvider.future);

      // 'ghost' not installed → dropped; extA present; extB appended
      expect(state.download.map((e) => e.id).toList(), ['extA', 'extB']);
    });
  });

  group('priorityProvider — reorderDownload persists', () {
    test('reorderDownload(0, 2) moves extB to index 1 and calls setDownloadPriority',
        () async {
      // Start: download = [extB, extA]  (extB saved first)
      final bridge = FakePriorityBridge(
        downloadPriority: ['extB'],
        metadataPriority: [],
      );
      final container = _makeContainer(bridge: bridge);
      addTearDown(container.dispose);

      await container.read(priorityProvider.future);

      // Move index 0 → index 2 (ReorderableListView semantics: insert before 2)
      // After adjustment: newI = 2-1 = 1 → list stays [extB, extA] → actually
      // removeAt(0)=extB, insert(1, extB) → [extA, extB]
      await container
          .read(priorityProvider.notifier)
          .reorderDownload(0, 2);

      final after = await container.read(priorityProvider.future);
      expect(after.download.map((e) => e.id).toList(), ['extA', 'extB']);
      expect(bridge.setDownloadCalls, hasLength(1));
      expect(bridge.setDownloadCalls.first, ['extA', 'extB']);
    });

    test('reorderMetadata persists via setMetadataPriority', () async {
      // savedOrder for metadata = ['extC'] → extC first, extB appended
      final bridge = FakePriorityBridge(
        downloadPriority: [],
        metadataPriority: ['extC'],
      );
      final container = _makeContainer(bridge: bridge);
      addTearDown(container.dispose);

      await container.read(priorityProvider.future);

      // Move index 0 (extC) to position 2 → ends up at index 1 → [extB, extC]
      await container
          .read(priorityProvider.notifier)
          .reorderMetadata(0, 2);

      final after = await container.read(priorityProvider.future);
      expect(after.metadata.map((e) => e.id).toList(), ['extB', 'extC']);
      expect(bridge.setMetadataCalls, hasLength(1));
      expect(bridge.setMetadataCalls.first, ['extB', 'extC']);
    });
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/installed_extension.dart';
import 'extensions_provider.dart';

class PriorityState {
  final List<InstalledExtension> download;
  final List<InstalledExtension> metadata;
  const PriorityState(this.download, this.metadata);
}

class PriorityController extends AsyncNotifier<PriorityState> {
  List<InstalledExtension> _reconcile(
    List<InstalledExtension> candidates,
    List<String> savedOrder,
  ) {
    final byId = {for (final e in candidates) e.id: e};
    final ordered = <InstalledExtension>[];
    for (final id in savedOrder) {
      final e = byId.remove(id);
      if (e != null) ordered.add(e);
    }
    ordered.addAll(byId.values); // new candidates not in saved order → append
    return ordered;
  }

  @override
  Future<PriorityState> build() async {
    final exts = await ref.watch(extensionsProvider.future);
    final b = ref.read(backendBridgeProvider);
    final dl = await b.getDownloadPriority();
    final md = await b.getMetadataPriority();
    final dlCand = exts.where((e) => e.hasDownloadProvider).toList();
    final mdCand = exts.where((e) => e.hasMetadataProvider).toList();
    return PriorityState(_reconcile(dlCand, dl), _reconcile(mdCand, md));
  }

  Future<void> reorderDownload(int oldI, int newI) async {
    final s = state.value;
    if (s == null) return;
    final list = [...s.download];
    if (newI > oldI) newI -= 1;
    list.insert(newI, list.removeAt(oldI));
    state = AsyncData(PriorityState(list, s.metadata));
    await ref
        .read(backendBridgeProvider)
        .setDownloadPriority(list.map((e) => e.id).toList());
  }

  Future<void> reorderMetadata(int oldI, int newI) async {
    final s = state.value;
    if (s == null) return;
    final list = [...s.metadata];
    if (newI > oldI) newI -= 1;
    list.insert(newI, list.removeAt(oldI));
    state = AsyncData(PriorityState(s.download, list));
    await ref
        .read(backendBridgeProvider)
        .setMetadataPriority(list.map((e) => e.id).toList());
  }
}

final priorityProvider =
    AsyncNotifierProvider<PriorityController, PriorityState>(
  PriorityController.new,
);

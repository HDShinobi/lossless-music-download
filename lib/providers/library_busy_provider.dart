import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/download_templates.dart';
import 'batch_re_enrich_provider.dart';
import 'download_dir_provider.dart';
import 'download_options_provider.dart';
import 'download_queue_provider.dart';

bool isActiveLibraryDownload(DownloadEntry entry) =>
    entry.status != 'done' && entry.status != 'failed';

final libraryQueueBusyProvider = Provider<bool>(
  (ref) => ref.watch(downloadQueueProvider).any(isActiveLibraryDownload),
);

bool isLibraryBusy({
  required bool queueRunning,
  required bool reEnrichRunning,
  required bool reorganizeRunning,
}) => queueRunning || reEnrichRunning || reorganizeRunning;

/// Shared admission guard. Jobs claim their running state before the first await.
final libraryBusyProvider = Provider<bool>((ref) {
  final queue = ref.watch(libraryQueueBusyProvider);
  final batch = ref.watch(batchReEnrichProvider).running;
  final reorganize = ref.watch(libraryReorganizeRunningProvider);
  return isLibraryBusy(
    queueRunning: queue,
    reEnrichRunning: batch,
    reorganizeRunning: reorganize,
  );
});

class LibraryReorganizeRunning extends Notifier<bool> {
  @override
  bool build() => false;

  /// [ignoreQueue]: single-file edits only conflict with the queue on their own
  /// path, which the caller checks via [isActiveLibraryDownloadPath].
  bool tryStart({bool ignoreQueue = false}) {
    if (isLibraryBusy(
      queueRunning: !ignoreQueue && ref.read(libraryQueueBusyProvider),
      reEnrichRunning: ref.read(batchReEnrichProvider).running,
      reorganizeRunning: state,
    )) {
      return false;
    }
    state = true;
    return true;
  }

  void finish() {
    if (ref.mounted) state = false;
  }
}

final libraryReorganizeRunningProvider =
    NotifierProvider<LibraryReorganizeRunning, bool>(
      LibraryReorganizeRunning.new,
    );

Uri _pathKey(String path) => File(path).absolute.uri.normalizePath();

/// A queue can receive new work after batch admission. Recheck each dispatch,
/// including the predicted destination before the worker has a filePath.
Future<bool> isActiveLibraryDownloadPath(Ref ref, String path) async {
  var active = ref.read(downloadQueueProvider).where(isActiveLibraryDownload);
  if (active.isEmpty) return false;
  final key = _pathKey(path);
  bool matchesFilePath(DownloadEntry entry) =>
      entry.filePath?.isNotEmpty == true && _pathKey(entry.filePath!) == key;
  if (active.any(matchesFilePath)) return true;
  await Future.wait([
    ref.read(folderOrganizationProvider.notifier).ready,
    ref.read(filenameTemplateProvider.notifier).ready,
    ref.read(albumFolderTemplateProvider.notifier).ready,
  ]);
  if (!ref.mounted) return true;
  final root = await ref.read(downloadDirProvider.future);
  if (!ref.mounted) return true;
  active = ref.read(downloadQueueProvider).where(isActiveLibraryDownload);
  return active.any((entry) {
    if (matchesFilePath(entry)) return true;
    final target = resolveDownloadTarget(
      root,
      entry.track,
      mode: ref.read(folderOrganizationProvider),
      filenameTemplate: ref.read(filenameTemplateProvider),
      albumFolderTemplate: ref.read(albumFolderTemplateProvider),
      quality: entry.quality,
    );
    final name = DownloadTemplates.preview(
      target.template,
      entry.track,
      quality: entry.quality,
    );
    // Same default extension as DownloadRequest / canDownloadAnywayProvider.
    return _pathKey('${target.dir}/$name.flac') == key;
  });
}

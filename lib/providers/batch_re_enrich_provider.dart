import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'library_manager.dart';
import 'library_provider.dart';
import 'library_busy_provider.dart';

class ReEnrichFailure {
  const ReEnrichFailure(this.path, this.title, this.error);
  final String path, title, error;
}

class BatchReEnrichState {
  const BatchReEnrichState({
    this.running = false,
    this.cancelled = false,
    this.completed = 0,
    this.total = 0,
    this.currentTitle = '',
    this.failures = const [],
  });
  final bool running, cancelled;
  final int completed, total;
  final String currentTitle;
  final List<ReEnrichFailure> failures;
}

/// Non-autoDispose: leaving a screen never drops an active job or its results.
class BatchReEnrich extends Notifier<BatchReEnrichState> {
  bool _cancel = false;
  @override
  BatchReEnrichState build() {
    ref.onDispose(() => _cancel = true);
    return const BatchReEnrichState();
  }

  void cancel() {
    _cancel = true;
    if (state.running) {
      state = BatchReEnrichState(
        running: true,
        cancelled: true,
        completed: state.completed,
        total: state.total,
        currentTitle: state.currentTitle,
        failures: state.failures,
      );
    }
  }

  void dismiss() {
    if (!state.running) state = const BatchReEnrichState();
  }

  Future<void> start(List<LibraryEntry> selection) async {
    if (selection.isEmpty ||
        isLibraryBusy(
          queueRunning: ref.read(libraryQueueBusyProvider),
          reEnrichRunning: state.running,
          reorganizeRunning: ref.read(libraryReorganizeRunningProvider),
        )) {
      return;
    }
    final items = {
      for (final entry in selection) entry.path: entry,
    }.values.toList();
    _cancel = false;
    state = BatchReEnrichState(running: true, total: items.length);
    final failures = <ReEnrichFailure>[];
    var completed = 0;
    final manager = ref.read(libraryManagerProvider.notifier);
    try {
      final options = await manager.reEnrichOptions();
      for (final entry in items) {
        if (_cancel || !ref.mounted) break;
        if (await isActiveLibraryDownloadPath(ref, entry.path)) continue;
        if (_cancel || !ref.mounted) break;
        state = BatchReEnrichState(
          running: true,
          completed: completed,
          total: items.length,
          currentTitle: entry.title ?? entry.name,
          failures: List.unmodifiable(failures),
        );
        try {
          await manager.reEnrichEntry(
            entry,
            options: options,
            refreshLibrary: false,
            inBatch: true,
          );
        } catch (e) {
          failures.add(
            ReEnrichFailure(entry.path, entry.title ?? entry.name, '$e'),
          );
        }
        completed++;
        if (!ref.mounted) return;
        state = BatchReEnrichState(
          running: true,
          cancelled: _cancel,
          completed: completed,
          total: items.length,
          currentTitle: entry.title ?? entry.name,
          failures: List.unmodifiable(failures),
        );
        await Future<void>.delayed(Duration.zero);
      }
    } catch (e) {
      completed = items.length;
      for (final entry in items) {
        failures.add(
          ReEnrichFailure(entry.path, entry.title ?? entry.name, '$e'),
        );
      }
    } finally {
      if (ref.mounted) {
        ref.invalidate(libraryProvider);
        state = BatchReEnrichState(
          cancelled: _cancel,
          completed: completed,
          total: items.length,
          failures: List.unmodifiable(failures),
        );
      }
    }
  }
}

final batchReEnrichProvider =
    NotifierProvider<BatchReEnrich, BatchReEnrichState>(BatchReEnrich.new);

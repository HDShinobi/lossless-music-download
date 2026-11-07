import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/library_busy_provider.dart';
import '../providers/download_dir_provider.dart';
import '../providers/download_history_provider.dart';
import '../providers/download_options_provider.dart';
import '../providers/library_provider.dart';
import '../services/library_reorganizer.dart';

/// Preview owns an immutable template snapshot; applying never re-resolves it.
class LibraryReorganizeScreen extends ConsumerStatefulWidget {
  const LibraryReorganizeScreen({super.key, this.selection});
  final Set<String>? selection;
  @override
  ConsumerState<LibraryReorganizeScreen> createState() =>
      _LibraryReorganizeState();
}

class _LibraryReorganizeState extends ConsumerState<LibraryReorganizeScreen> {
  LibraryReorganizer? _service;
  LibraryReorganizationPlan? _plan;
  LibraryReorganizationResult? _result;
  Object? _error;
  bool _running = false, _cancel = false;
  int _done = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final running = ref.read(libraryReorganizeRunningProvider.notifier);
    if (!running.tryStart()) {
      setState(() => _error = AppLocalizations.of(context).reorganizeBusy);
      return;
    }
    try {
      await Future.wait([
        ref.read(filenameTemplateProvider.notifier).ready,
        ref.read(albumFolderTemplateProvider.notifier).ready,
        ref.read(folderOrganizationProvider.notifier).ready,
      ]);
      if (!mounted) return;
      final root = await ref.read(downloadDirProvider.future);
      if (!mounted) return;
      final history = await ref.read(historyDatabaseProvider.future);
      if (!mounted) return;
      final tags = await ref.read(libraryProvider.future);
      if (!mounted) return;
      // Queue admission is independent of this lock; it may change while loading.
      if (ref.read(libraryQueueBusyProvider)) {
        setState(() => _error = AppLocalizations.of(context).reorganizeBusy);
        return;
      }
      final service = LibraryReorganizer(history);
      final plan = await service.plan(
        root: root,
        mode: ref.read(folderOrganizationProvider),
        filenameTemplate: ref.read(filenameTemplateProvider),
        albumFolderTemplate: ref.read(albumFolderTemplateProvider),
        selection: widget.selection,
        tags: tags,
      );
      if (mounted) {
        setState(() {
          _service = service;
          _plan = plan;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      running.finish();
    }
  }

  Future<void> _apply() async {
    if (_running || _result != null) return;
    final running = ref.read(libraryReorganizeRunningProvider.notifier);
    if (!running.tryStart()) {
      setState(() => _error = AppLocalizations.of(context).reorganizeBusy);
      return;
    }
    setState(() {
      _running = true;
      _cancel = false;
    });
    try {
      final result = await _service!.apply(
        _plan!,
        isCancelled: () =>
            _cancel || !mounted || ref.read(libraryQueueBusyProvider),
        onProgress: (done, _) {
          if (mounted) setState(() => _done = done);
        },
      );
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      running.finish();
      if (mounted) {
        ref.read(historyRevisionProvider.notifier).changed();
        ref.invalidate(libraryProvider);
        setState(() => _running = false);
      }
    }
  }

  @override
  void dispose() {
    _cancel = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final plan = _plan;
    final result = _result;
    String status(ReorganizationStatus value) => switch (value) {
      ReorganizationStatus.ready => t.reorganizeReady,
      ReorganizationStatus.unchanged => t.reorganizeUnchanged,
      ReorganizationStatus.conflict => t.reorganizeConflict,
      ReorganizationStatus.missing => t.reorganizeMissing,
      ReorganizationStatus.unsafe => t.reorganizeUnsafe,
    };
    return PopScope(
      canPop: !_running,
      child: Scaffold(
        appBar: AppBar(title: Text(t.reorganizeTitle)),
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(t.reorganizeError('$_error')),
                ),
              )
            : plan == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      t.reorganizePreview(
                        plan.ready,
                        plan.unchanged,
                        plan.items
                            .where(
                              (i) => i.status == ReorganizationStatus.conflict,
                            )
                            .length,
                      ),
                    ),
                  ),
                  if (_running) ...[
                    LinearProgressIndicator(
                      value: plan.ready == 0 ? 0 : _done / plan.ready,
                    ),
                    Text(t.reorganizeProgress(_done, plan.ready)),
                  ],
                  if (result != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '${t.reorganizeSummary(result.moved, result.skipped)}'
                        '${result.cancelled ? '\n${t.reorganizeCancelled}' : ''}',
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: plan.items.length,
                      itemBuilder: (context, index) {
                        final item = plan.items[index];
                        return ListTile(
                          isThreeLine: true,
                          title: Text('${item.source}\n→ ${item.target}'),
                          subtitle: Text(
                            result?.errors[item.source] ?? status(item.status),
                          ),
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _running
                          ? TextButton(
                              onPressed: _cancel
                                  ? null
                                  : () => setState(() => _cancel = true),
                              child: Text(
                                _cancel
                                    ? t.batchRefreshCancelling
                                    : t.commonCancel,
                              ),
                            )
                          : result == null
                          ? FilledButton(
                              onPressed: plan.ready == 0 ? null : _apply,
                              child: Text(t.reorganizeApply),
                            )
                          : TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(t.batchRefreshDismiss),
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

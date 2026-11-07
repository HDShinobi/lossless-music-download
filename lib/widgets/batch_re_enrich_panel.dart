import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/batch_re_enrich_provider.dart';

/// Results remain in the provider until dismissed, including after navigation.
class BatchReEnrichPanel extends ConsumerWidget {
  const BatchReEnrichPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(batchReEnrichProvider);
    if (state.total == 0) return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    final runner = ref.read(batchReEnrichProvider.notifier);
    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      state.running
                          ? t.batchRefreshProgress(state.completed, state.total)
                          : state.cancelled
                          ? t.batchRefreshCancelled
                          : t.reEnrichDone,
                    ),
                  ),
                  if (state.running)
                    TextButton(
                      onPressed: state.cancelled ? null : runner.cancel,
                      child: Text(
                        state.cancelled ? t.batchRefreshCancelling : t.cancel,
                      ),
                    )
                  else
                    IconButton(
                      tooltip: t.batchRefreshDismiss,
                      onPressed: runner.dismiss,
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
              if (state.running) ...[
                LinearProgressIndicator(value: state.completed / state.total),
                Text(
                  state.currentTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ] else
                Text(
                  t.batchRefreshSummary(
                    state.completed - state.failures.length,
                    state.total,
                    state.failures.length,
                  ),
                ),
              if (state.failures.isNotEmpty)
                TextButton(
                  onPressed: () => unawaited(
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(t.batchRefreshErrors),
                        content: SizedBox(
                          width: double.maxFinite,
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              for (final failure in state.failures)
                                ListTile(
                                  title: Text(failure.title),
                                  subtitle: Text(
                                    '${failure.path}\n${failure.error}',
                                  ),
                                ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(t.batchRefreshDismiss),
                          ),
                        ],
                      ),
                    ),
                  ),
                  child: Text(t.batchRefreshErrors),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/download_queue_provider.dart';
import '../providers/extensions_provider.dart';
import '../theme/app_tokens.dart';
import '../util/format_progress.dart';
import '../util/queue_view.dart';

/// Renders a single [QueueItemView] in the brand card style with a
/// mono status line, optional cover art, and a per-state trailing action.
class QueueItem extends ConsumerWidget {
  const QueueItem({super.key, required this.view});

  final QueueItemView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final bridge = ref.read(backendBridgeProvider);

    final item = view.progress;

    // Map status string to a _ItemState enum for clean dispatch
    final state = _resolveState(item.status);

    // Determine colours by state
    final Color statusColor;
    switch (state) {
      case _ItemState.downloading:
        statusColor = scheme.primary;
      case _ItemState.finalizing:
        statusColor = scheme.primary;
      case _ItemState.done:
        statusColor = scheme.primary;
      case _ItemState.failed:
        statusColor = tokens.down;
      case _ItemState.queued:
        statusColor = tokens.muted2;
      case _ItemState.unknown:
        statusColor = tokens.muted2;
    }

    // Build the mono progress status line text
    final String statusLine;
    switch (state) {
      case _ItemState.downloading:
        statusLine = formatProgressLine(
          doneBytes: item.bytesReceived,
          totalBytes: view.totalBytes,
          speedBytesPerSec: view.speedBytesPerSec,
          eta: view.eta,
        );
      case _ItemState.finalizing:
        statusLine = t.queueStatusFinalizing;
      case _ItemState.queued:
        statusLine = t.queueStatusQueued;
      case _ItemState.failed:
        statusLine = t.queueStatusFailed;
      case _ItemState.done:
        statusLine = t.queueStatusDone;
      case _ItemState.unknown:
        statusLine = item.status;
    }

    // Trailing action
    Widget trailing;
    switch (state) {
      case _ItemState.downloading:
        trailing = IconButton(
          icon: Icon(Icons.cancel_outlined, color: scheme.primary),
          tooltip: t.cancel,
          onPressed: () => unawaited(
            bridge.cancelDownload(item.itemId).catchError((_) {}),
          ),
        );
      case _ItemState.finalizing:
        trailing = const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _ItemState.failed:
        // Retry via the persistent queue controller (removes old entry,
        // re-enqueues the track from scratch).
        trailing = IconButton(
          icon: Icon(Icons.refresh, color: tokens.down),
          tooltip: t.queueStatusFailed,
          onPressed: () => ref
              .read(downloadQueueProvider.notifier)
              .retry(item.itemId),
        );
      case _ItemState.done:
        trailing = Icon(Icons.check_circle_outline, color: scheme.primary);
      case _ItemState.queued:
        trailing = Icon(Icons.schedule, color: tokens.muted2);
      case _ItemState.unknown:
        trailing = Icon(Icons.help_outline, color: tokens.muted2);
    }

    // Cover art: show network image if coverUrl available, else placeholder.
    final coverUrl = view.track?.coverUrl;
    final Widget cover;
    if (coverUrl != null) {
      cover = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 46,
          height: 46,
          child: Image.network(
            coverUrl,
            fit: BoxFit.cover,
            errorBuilder: (ctx, err, trace) => _coverPlaceholder(tokens),
          ),
        ),
      );
    } else {
      cover = _coverPlaceholder(tokens);
    }

    // Title: track name if known, itemId as fallback
    final title = view.track?.name ?? item.itemId;

    final cardContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          cover,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  statusLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.mono.copyWith(
                    fontSize: 11,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          trailing,
        ],
      ),
    );

    // Card with brand styling: surface + accentLine border, radius 14
    final card = Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.accentLine.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Progress fill — soft accent bar behind content
          if (item.progress > 0)
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: item.progress.clamp(0.0, 1.0),
                  child: Container(
                    color: tokens.accentSoft,
                  ),
                ),
              ),
            ),
          cardContent,
        ],
      ),
    );

    // Swipe-to-dismiss (end-to-start) to cancel the download
    return Dismissible(
      key: ValueKey(item.itemId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: tokens.downSoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.delete_sweep_outlined, color: tokens.down),
      ),
      onDismissed: (_) =>
          ref.read(downloadQueueProvider.notifier).remove(item.itemId),
      child: card,
    );
  }
}

Widget _coverPlaceholder(AppTokens tokens) => Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: tokens.surface3,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.music_note, size: 22, color: tokens.muted2),
    );

enum _ItemState { downloading, finalizing, done, failed, queued, unknown }

_ItemState _resolveState(String status) {
  final s = status.toLowerCase();
  if (s.contains('download')) return _ItemState.downloading;
  // Backend reports "metadata" while writing tags/cover after the bytes land.
  if (s.contains('metadata') ||
      s.contains('finaliz') ||
      s.contains('process') ||
      s.contains('writ')) {
    return _ItemState.finalizing;
  }
  if (s.contains('complet') || s.contains('done') || s.contains('success')) {
    return _ItemState.done;
  }
  if (s.contains('fail') || s.contains('error')) return _ItemState.failed;
  if (s.contains('queue') || s.contains('pending') || s.contains('wait')) {
    return _ItemState.queued;
  }
  return _ItemState.unknown;
}

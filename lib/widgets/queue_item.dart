import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/download_progress.dart';
import '../providers/extensions_provider.dart';
import '../theme/app_tokens.dart';
import '../util/format_progress.dart';

// TODO(carry-over): The queue currently lacks track name and cover art —
// only itemId is available as an identifier. A future backend progress
// enrichment pass is needed to supply track metadata (name, artist, cover).
// Speed and ETA are also not available from DownloadProgress; they require
// a separate backend stream.

/// Renders a single [DownloadProgress] item in the brand card style with a
/// mono status line and a per-state progress fill + trailing action.
class QueueItem extends ConsumerWidget {
  const QueueItem({super.key, required this.item});

  final DownloadProgress item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final bridge = ref.read(backendBridgeProvider);

    // Map status string to a _ItemState enum for clean dispatch
    final state = _resolveState(item.status);

    // Determine colours by state
    final Color statusColor;
    switch (state) {
      case _ItemState.downloading:
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
    // TODO(carry-over): speed and ETA not available from DownloadProgress;
    // omitted until backend exposes them.
    final String statusLine;
    switch (state) {
      case _ItemState.downloading:
        final int? total = (item.progress > 0 && item.bytesReceived > 0)
            ? (item.bytesReceived / item.progress).round()
            : null;
        statusLine = formatProgressLine(
          doneBytes: item.bytesReceived,
          totalBytes: total,
        );
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
      case _ItemState.failed:
        // TODO(carry-over): true retry needs re-enqueue support from backend.
        // For now, cancel is the best-effort "clear" action.
        trailing = IconButton(
          icon: Icon(Icons.refresh, color: tokens.down),
          tooltip: t.queueStatusFailed,
          onPressed: () => unawaited(
            bridge.cancelDownload(item.itemId).catchError((_) {}),
          ),
        );
      case _ItemState.done:
        trailing = Icon(Icons.check_circle_outline, color: scheme.primary);
      case _ItemState.queued:
        trailing = Icon(Icons.schedule, color: tokens.muted2);
      case _ItemState.unknown:
        trailing = Icon(Icons.help_outline, color: tokens.muted2);
    }

    // Cover placeholder (46x46 rounded box with a music-note icon)
    final coverPlaceholder = Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: tokens.surface3,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.music_note, size: 22, color: tokens.muted2),
    );

    final cardContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          coverPlaceholder,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemId,
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
      onDismissed: (_) => unawaited(
        bridge.cancelDownload(item.itemId).catchError((_) {}),
      ),
      child: card,
    );
  }
}

enum _ItemState { downloading, done, failed, queued, unknown }

_ItemState _resolveState(String status) {
  final s = status.toLowerCase();
  if (s.contains('download')) return _ItemState.downloading;
  if (s.contains('complet') || s.contains('done') || s.contains('success')) {
    return _ItemState.done;
  }
  if (s.contains('fail') || s.contains('error')) return _ItemState.failed;
  if (s.contains('queue') || s.contains('pending') || s.contains('wait')) {
    return _ItemState.queued;
  }
  return _ItemState.unknown;
}

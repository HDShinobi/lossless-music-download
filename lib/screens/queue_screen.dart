import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';

import '../models/download_progress.dart';
import '../providers/download_queue_provider.dart';
import '../providers/downloads_provider.dart';
import '../util/queue_view.dart';
import '../widgets/queue_item.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);

    // Keep the backend poll alive while this screen is visible.
    ref.watch(downloadsProvider);

    // Watch the client-side persistent queue.
    final entries = ref.watch(downloadQueueProvider);

    final reason = ref.watch(queuePauseReasonProvider);
    final controller = ref.read(downloadQueueProvider.notifier);
    final Widget body;
    if (entries.isEmpty) {
      body = Center(child: Text(t.queueEmpty));
    } else {
      body = ListView.builder(
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final e = entries[index];
          return QueueItem(view: _viewOf(e));
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(t.tabQueue), actions: [
        IconButton(
          tooltip: reason == 'paused' ? t.queueResume : t.queuePause,
          icon: Icon(reason == 'paused' ? Icons.play_arrow : Icons.pause),
          onPressed: reason == 'paused' ? controller.resume : controller.pause,
        ),
        PopupMenuButton<String>(
          onSelected: (value) => value == 'clear'
              ? controller.clearCompleted() : controller.retryAllFailed(),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'clear', enabled: entries.any((e) => e.status == 'done'),
              child: Text(t.queueClearCompleted)),
            PopupMenuItem(value: 'retry', enabled: entries.any((e) => e.status == 'failed'),
              child: Text(t.queueRetryAllFailed)),
          ],
        ),
      ]),
      body: Column(children: [
        if (reason != null) ListTile(
          leading: Icon(reason == 'waiting_wifi' ? Icons.wifi_off : Icons.pause_circle_outline),
          title: Text(reason == 'waiting_wifi' ? t.queueWaitingWifi : t.queuePaused),
        ),
        Expanded(child: body),
      ]),
    );
  }

  QueueItemView _viewOf(DownloadEntry e) {
    return QueueItemView(
      progress: DownloadProgress(
        itemId: e.itemId,
        status: e.status,
        progress: e.progress,
        bytesReceived: e.bytesReceived,
      ),
      track: e.track,
      totalBytes: e.totalBytes,
      speedBytesPerSec: e.speedBytesPerSec,
      eta: e.eta,
      error: e.error,
      service: e.service,
      resolvedService: e.resolvedService,
    );
  }
}

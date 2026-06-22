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
      appBar: AppBar(title: Text(t.tabQueue)),
      body: body,
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
    );
  }
}

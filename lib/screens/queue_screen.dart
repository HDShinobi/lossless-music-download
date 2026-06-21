import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';

import '../models/download_progress.dart';
import '../providers/downloads_provider.dart';
import '../providers/extensions_provider.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final asyncDownloads = ref.watch(downloadsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.tabQueue)),
      body: asyncDownloads.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text(e.toString())),
        data: (items) {
          if (items.isEmpty) {
            return Center(child: Text(t.queueEmpty));
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _DownloadTile(item: item);
            },
          );
        },
      ),
    );
  }
}

class _DownloadTile extends ConsumerWidget {
  const _DownloadTile({required this.item});
  final DownloadProgress item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final bridge = ref.read(backendBridgeProvider);

    return ListTile(
      title: Text(item.itemId),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: item.progress),
          const SizedBox(height: 4),
          Text(item.status),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.cancel_outlined),
        tooltip: t.cancel,
        onPressed: () => unawaited(bridge.cancelDownload(item.itemId).catchError((_) {})),
      ),
    );
  }
}

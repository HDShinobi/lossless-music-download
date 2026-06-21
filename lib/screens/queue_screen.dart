import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';

import '../providers/downloads_provider.dart';
import '../widgets/queue_item.dart';

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
        error: (e, st) => Center(child: Text(t.queueError)),
        data: (items) {
          if (items.isEmpty) {
            return Center(child: Text(t.queueEmpty));
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return QueueItem(item: item);
            },
          );
        },
      ),
    );
  }
}


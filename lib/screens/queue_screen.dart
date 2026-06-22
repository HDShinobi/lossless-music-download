import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';

import '../providers/download_labels_provider.dart';
import '../providers/downloads_provider.dart';
import '../widgets/queue_item.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);

    // Keep the stream polling alive
    ref.watch(downloadsProvider);

    // Watch the enriched view list
    final views = ref.watch(queueViewProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.tabQueue)),
      body: views.isEmpty
          ? Center(child: Text(t.queueEmpty))
          : ListView.builder(
              itemCount: views.length,
              itemBuilder: (context, index) {
                final v = views[index];
                return QueueItem(view: v);
              },
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import '../models/installed_extension.dart';
import '../providers/priority_provider.dart';

class PriorityTab extends ConsumerWidget {
  const PriorityTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final asyncState = ref.watch(priorityProvider);

    return asyncState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text(err.toString())),
      data: (state) => _PriorityBody(
        downloadList: state.download,
        metadataList: state.metadata,
        t: t,
        onReorderDownload: (oldI, newI) =>
            ref.read(priorityProvider.notifier).reorderDownload(oldI, newI),
        onReorderMetadata: (oldI, newI) =>
            ref.read(priorityProvider.notifier).reorderMetadata(oldI, newI),
      ),
    );
  }
}

class _PriorityBody extends StatelessWidget {
  const _PriorityBody({
    required this.downloadList,
    required this.metadataList,
    required this.t,
    required this.onReorderDownload,
    required this.onReorderMetadata,
  });

  final List<InstalledExtension> downloadList;
  final List<InstalledExtension> metadataList;
  final AppLocalizations t;
  final void Function(int, int) onReorderDownload;
  final void Function(int, int) onReorderMetadata;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              t.priorityIntro,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          _GroupSection(
            title: t.groupDownload,
            items: downloadList,
            emptyText: t.priorityEmpty,
            onReorder: onReorderDownload,
          ),
          const SizedBox(height: 24),
          _GroupSection(
            title: t.groupMetadata,
            items: metadataList,
            emptyText: t.priorityEmpty,
            onReorder: onReorderMetadata,
          ),
        ],
      ),
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.title,
    required this.items,
    required this.emptyText,
    required this.onReorder,
  });

  final String title;
  final List<InstalledExtension> items;
  final String emptyText;
  final void Function(int, int) onReorder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              emptyText,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          )
        else
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: onReorder,
            children: [
              for (int i = 0; i < items.length; i++)
                ListTile(
                  key: ValueKey(items[i].id),
                  leading: CircleAvatar(
                    radius: 14,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  title: Text(items[i].displayName),
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: const Icon(Icons.drag_handle),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

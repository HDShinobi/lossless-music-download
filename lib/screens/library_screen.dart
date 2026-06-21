import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/providers/library_provider.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final asyncEntries = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.tabLibrary),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t.refresh,
            onPressed: () => ref.invalidate(libraryProvider),
          ),
        ],
      ),
      body: asyncEntries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(t.libraryError)),
        data: (entries) {
          if (entries.isEmpty) {
            return Center(child: Text(t.libraryEmpty));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  t.libraryCount(entries.length),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final sizeMb = (entry.sizeBytes / 1048576).toStringAsFixed(1);
                    return ListTile(
                      leading: const Icon(Icons.music_note),
                      title: Text(entry.name),
                      subtitle: Text('$sizeMb ${t.unitMb}'),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

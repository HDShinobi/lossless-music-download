import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';

import '../l10n/app_localizations.dart';
import '../providers/download_history_provider.dart';
import '../services/history_database.dart';

class DownloadHistoryScreen extends ConsumerStatefulWidget {
  const DownloadHistoryScreen({super.key});
  @override
  ConsumerState<DownloadHistoryScreen> createState() =>
      _DownloadHistoryScreenState();
}

class _DownloadHistoryScreenState extends ConsumerState<DownloadHistoryScreen> {
  String _search = '';
  int _page = 0;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final entries = ref.watch(
      downloadHistoryProvider((search: _search, page: _page)),
    );
    return Scaffold(
      appBar: AppBar(title: Text(t.downloadHistory)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: t.historySearchHint,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) => setState(() {
                _search = value.trim();
                _page = 0;
              }),
            ),
          ),
          Expanded(
            child: entries.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(child: Text(t.historyError)),
              data: (rows) => rows.isEmpty
                  ? Center(child: Text(t.historyEmpty))
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final entry = rows[index];
                        return ListTile(
                          leading: const Icon(Icons.download_done),
                          title: Text(entry.track.name),
                          subtitle: Text(
                            '${entry.track.artists}\n${DateFormat.yMd(Localizations.localeOf(context).toString()).add_Hm().format(entry.downloadedAt)}'
                            '${entry.quality == null ? '' : ' · ${entry.quality}'}',
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) async {
                              if (action == 'location') {
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        _FileLocationScreen(entry: entry),
                                  ),
                                );
                              } else {
                                try {
                                  final db = await ref.read(
                                    historyDatabaseProvider.future,
                                  );
                                  await db.remove(entry.id);
                                  if (mounted) {
                                    ref
                                        .read(historyRevisionProvider.notifier)
                                        .changed();
                                  }
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(t.historyError)),
                                    );
                                  }
                                }
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'location',
                                child: Text(t.historyOpenLocation),
                              ),
                              PopupMenuItem(
                                value: 'remove',
                                child: Text(t.historyRemove),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _page > 0 ? () => setState(() => _page--) : null,
                child: Text(t.historyPrevious),
              ),
              TextButton(
                onPressed: entries.value?.length == 100
                    ? () => setState(() => _page++)
                    : null,
                child: Text(t.historyNext),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Open the actual containing directory with the app's existing storage grant.
/// This works even on devices without a file-manager ACTION_VIEW handler.
class _FileLocationScreen extends StatefulWidget {
  final HistoryEntry entry;
  const _FileLocationScreen({required this.entry});
  @override
  State<_FileLocationScreen> createState() => _FileLocationScreenState();
}

class _FileLocationScreenState extends State<_FileLocationScreen> {
  late final Directory _folder = File(widget.entry.filePath).parent;
  late final Future<List<FileSystemEntity>> _files = _folder
      .list(followLinks: false)
      .take(500)
      .toList()
      .then(
        (files) => files
          ..sort((a, b) {
            if (a.path == widget.entry.filePath) return -1;
            if (b.path == widget.entry.filePath) return 1;
            return a.path.compareTo(b.path);
          }),
      );
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.historyOpenLocation)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(_folder.path),
          ),
          Expanded(
            child: FutureBuilder<List<FileSystemEntity>>(
              future: _files,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text(t.historyLocationUnavailable));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView(
                  children: [
                    for (final file in snapshot.data!)
                      ListTile(
                        selected: file.path == widget.entry.filePath,
                        leading: Icon(
                          file is Directory
                              ? Icons.folder_outlined
                              : Icons.audio_file_outlined,
                        ),
                        title: Text(file.path.split('/').last),
                        onTap: file is File
                            ? () async {
                                final result = await OpenFilex.open(file.path);
                                if (result.type != ResultType.done &&
                                    context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        t.historyLocationUnavailable,
                                      ),
                                    ),
                                  );
                                }
                              }
                            : null,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

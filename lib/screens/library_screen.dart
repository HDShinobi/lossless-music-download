import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/providers/library_provider.dart';
import 'package:lossless_music_download/widgets/library_track_tile.dart';
import 'package:lossless_music_download/widgets/serve_banner.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  int _segment = 0; // 0=All, 1=Albums, 2=Singles

  @override
  Widget build(BuildContext context) {
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
              // Segment toggle buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ToggleButtons(
                  isSelected: [
                    _segment == 0,
                    _segment == 1,
                    _segment == 2,
                  ],
                  onPressed: (index) => setState(() => _segment = index),
                  borderRadius: BorderRadius.circular(8),
                  constraints: const BoxConstraints(minHeight: 36, minWidth: 72),
                  children: [
                    Text(t.libraryAll),
                    Text(t.libraryAlbums),
                    Text(t.librarySingles),
                  ],
                ),
              ),
              // List area
              Expanded(
                child: _buildList(context, entries),
              ),
              // Serve banner always at bottom
              ServeBanner(count: entries.length),
            ],
          );
        },
      ),
    );
  }

  Widget _buildList(BuildContext context, List<LibraryEntry> entries) {
    switch (_segment) {
      case 1:
        return _buildAlbumsView(context, entries);
      case 2:
        return _buildSinglesView(entries);
      default:
        return _buildAllView(entries);
    }
  }

  Widget _buildAllView(List<LibraryEntry> entries) {
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) => LibraryTrackTile(
        entry: entries[index],
        onTap: () => context.go('/library/verified', extra: entries[index]),
      ),
    );
  }

  Widget _buildAlbumsView(BuildContext context, List<LibraryEntry> entries) {
    // Group entries that have an albumName by (artistName, albumName)
    final grouped = <(String, String), List<LibraryEntry>>{};
    for (final entry in entries) {
      if (entry.albumName == null) continue;
      final key = (entry.artistName ?? '', entry.albumName!);
      grouped.putIfAbsent(key, () => []).add(entry);
    }

    if (grouped.isEmpty) {
      return const Center(child: SizedBox.shrink());
    }

    // Flatten into a list of widgets: header + tiles
    final widgets = <Widget>[];
    for (final kv in grouped.entries) {
      final artist = kv.key.$1;
      final album = kv.key.$2;
      final tracks = kv.value;
      widgets.add(
        ListTile(
          title: Text(album),
          subtitle: Text('$artist · ${AppLocalizations.of(context).albumTrackCount(tracks.length)}'),
        ),
      );
      for (final track in tracks) {
        widgets.add(LibraryTrackTile(
          entry: track,
          onTap: () => context.go('/library/verified', extra: track),
        ));
      }
    }

    return ListView(children: widgets);
  }

  Widget _buildSinglesView(List<LibraryEntry> entries) {
    final singles =
        entries.where((e) => e.albumName == null).toList();
    if (singles.isEmpty) {
      return const Center(child: SizedBox.shrink());
    }
    return ListView.builder(
      itemCount: singles.length,
      itemBuilder: (context, index) => LibraryTrackTile(
        entry: singles[index],
        onTap: () =>
            context.go('/library/verified', extra: singles[index]),
      ),
    );
  }
}

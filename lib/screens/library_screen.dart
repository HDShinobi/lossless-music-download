import 'dart:io';

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
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.toLowerCase().trim());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<LibraryEntry> _filter(List<LibraryEntry> all) {
    if (_searchQuery.isEmpty) return all;
    return all.where((e) {
      final title = (e.title ?? e.name).toLowerCase();
      final artist = e.artistName?.toLowerCase() ?? '';
      return title.contains(_searchQuery) || artist.contains(_searchQuery);
    }).toList();
  }

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
              // Search field
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: t.librarySearchHint,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 12),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
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
    final t = AppLocalizations.of(context);
    final filtered = _filter(entries);
    if (filtered.isEmpty && _searchQuery.isNotEmpty) {
      return Center(child: Text(t.libraryNoResults));
    }
    switch (_segment) {
      case 1: return _buildAlbumsView(context, filtered);
      case 2: return _buildSinglesView(filtered);
      default: return _buildAllView(filtered);
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

    final albums = grouped.entries.toList();

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final kv = albums[index];
        final artist = kv.key.$1;
        final album = kv.key.$2;
        final tracks = kv.value;
        // Pick the first track that has a local cover extracted.
        final coverEntry =
            tracks.firstWhere((e) => e.coverPath != null, orElse: () => tracks.first);
        return _AlbumTile(
          artist: artist,
          album: album,
          tracks: tracks,
          coverEntry: coverEntry,
          onTap: () => context.go('/library/verified', extra: tracks.first),
        );
      },
    );
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

// ---------------------------------------------------------------------------
// Album cover grid tile
// ---------------------------------------------------------------------------

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({
    required this.artist,
    required this.album,
    required this.tracks,
    required this.coverEntry,
    required this.onTap,
  });

  final String artist;
  final String album;
  final List<LibraryEntry> tracks;
  final LibraryEntry coverEntry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final coverPath = coverEntry.coverPath;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: coverPath != null
                  ? Image.file(
                      File(coverPath),
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _coverPlaceholder(cs),
                    )
                  : _coverPlaceholder(cs),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 8, 9, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  if (artist.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    '${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'}',
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverPlaceholder(ColorScheme cs) => Container(
        color: cs.surfaceContainerHigh,
        child: Center(
          child: Icon(Icons.album_outlined, size: 36, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
        ),
      );
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/providers/library_provider.dart';
import 'package:lossless_music_download/widgets/library_track_tile.dart';

/// Route arguments for [LibraryAlbumScreen] (`/library/album`).
class LibraryAlbumRouteArgs {
  const LibraryAlbumRouteArgs({required this.artistName, required this.albumName});
  final String artistName;
  final String albumName;
}

/// The tracks of one downloaded album, in album order. Mirrors upstream
/// SpotiFLAC's DownloadedAlbumScreen lookup: match on artist+album
/// case-insensitively, sort by disc, then track number (untagged last),
/// then title.
List<LibraryEntry> albumTracksFor(
  List<LibraryEntry> all,
  String artistName,
  String albumName,
) {
  final key = '${albumName.toLowerCase()}|${artistName.toLowerCase()}';
  String titleOf(LibraryEntry e) => e.title ?? e.name;
  return all.where((e) {
    if (e.albumName == null) return false;
    return '${e.albumName!.toLowerCase()}|${(e.artistName ?? '').toLowerCase()}' == key;
  }).toList()
    ..sort((a, b) {
      final aDisc = a.discNumber ?? 1;
      final bDisc = b.discNumber ?? 1;
      if (aDisc != bDisc) return aDisc.compareTo(bDisc);
      final aNum = a.trackNumber ?? 999;
      final bNum = b.trackNumber ?? 999;
      if (aNum != bNum) return aNum.compareTo(bNum);
      return titleOf(a).toLowerCase().compareTo(titleOf(b).toLowerCase());
    });
}

/// Groups album-ordered [tracks] by disc number (null → disc 1), keys sorted.
Map<int, List<LibraryEntry>> groupTracksByDisc(List<LibraryEntry> tracks) {
  final groups = <int, List<LibraryEntry>>{};
  for (final track in tracks) {
    groups.putIfAbsent(track.discNumber ?? 1, () => []).add(track);
  }
  final sortedKeys = groups.keys.toList()..sort();
  return {for (final k in sortedKeys) k: groups[k]!};
}

class LibraryAlbumScreen extends ConsumerWidget {
  const LibraryAlbumScreen({
    super.key,
    required this.artistName,
    required this.albumName,
  });

  final String artistName;
  final String albumName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final asyncEntries = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(albumName)),
      body: asyncEntries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(t.libraryError)),
        data: (entries) {
          final tracks = albumTracksFor(entries, artistName, albumName);
          if (tracks.isEmpty) {
            return Center(child: Text(t.libraryEmpty));
          }
          final discs = groupTracksByDisc(tracks);
          final showDiscHeaders = discs.length > 1;

          final children = <Widget>[
            _AlbumHeader(
              artistName: artistName,
              albumName: albumName,
              tracks: tracks,
            ),
            const SizedBox(height: 4),
            for (final disc in discs.entries) ...[
              if (showDiscHeaders) _DiscSeparator(number: disc.key),
              for (final track in disc.value)
                LibraryTrackTile(
                  entry: track,
                  onTap: () =>
                      context.push('/library/verified', extra: track),
                ),
            ],
          ];

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: children,
          );
        },
      ),
    );
  }
}

class _AlbumHeader extends StatelessWidget {
  const _AlbumHeader({
    required this.artistName,
    required this.albumName,
    required this.tracks,
  });

  final String artistName;
  final String albumName;
  final List<LibraryEntry> tracks;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final coverPath = tracks
        .firstWhere((e) => e.coverPath != null, orElse: () => tracks.first)
        .coverPath;
    final formats = tracks.map((e) => e.format).toSet().join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 112,
              height: 112,
              child: coverPath != null
                  ? Image.file(
                      File(coverPath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, e, s) => _placeholder(cs),
                    )
                  : _placeholder(cs),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (artistName.isNotEmpty)
                  Text(
                    artistName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                const SizedBox(height: 6),
                Text(
                  '${t.albumTrackCount(tracks.length)} · $formats',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) => Container(
        color: cs.surfaceContainerHigh,
        child: Icon(
          Icons.album_outlined,
          size: 40,
          color: cs.onSurfaceVariant.withValues(alpha: 0.4),
        ),
      );
}

class _DiscSeparator extends StatelessWidget {
  const _DiscSeparator({required this.number});
  final int number;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          Icon(Icons.album, size: 15, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            t.discLabel(number),
            style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

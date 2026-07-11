import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import '../models/home_feed.dart';
import '../models/search_entities.dart';
import '../models/track.dart';
import '../providers/download_options_provider.dart';
import '../providers/download_queue_provider.dart';
import '../providers/extensions_provider.dart';
import '../providers/home_feed_provider.dart';
import '../providers/search_provider.dart';
import '../theme/app_tokens.dart';
import '../widgets/download_sheet.dart';
import '../widgets/track_tile.dart';
import 'album_screen.dart';
import 'artist_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  SearchFilter _filter = SearchFilter.all;
  final _searchController = TextEditingController();
  bool _queryEmpty = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Selection helpers
  // -------------------------------------------------------------------------

  void _enterSelectionMode(String trackId) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(trackId);
    });
  }

  void _toggleSelection(String trackId) {
    setState(() {
      if (_selectedIds.contains(trackId)) {
        _selectedIds.remove(trackId);
      } else {
        _selectedIds.add(trackId);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  // -------------------------------------------------------------------------
  // Single-track download (normal mode)
  // -------------------------------------------------------------------------

  Future<void> _onDownload(BuildContext context, Track track) async {
    final askBefore = ref.read(askBeforeDownloadProvider);
    if (askBefore) {
      await _showPickerSheet(context, track);
      return;
    }
    // Quick enqueue: first enabled download source, hires quality.
    final t = AppLocalizations.of(context);
    final queue = ref.read(downloadQueueProvider.notifier);
    final sources = ref
            .read(extensionsProvider)
            .value
            ?.where((e) => e.enabled && e.hasDownloadProvider)
            .toList() ??
        [];
    unawaited(
      queue
          .enqueue(
            track,
            service: sources.isNotEmpty ? sources.first.id : null,
            quality: 'hires',
          )
          .catchError((Object _) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.downloadFailed)),
          );
        }
      }),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.downloadStarted)),
      );
    }
  }

  Future<void> _showPickerSheet(BuildContext context, Track track) async {
    final t = AppLocalizations.of(context);
    final queue = ref.read(downloadQueueProvider.notifier);
    final sources = ref
            .read(extensionsProvider)
            .value
            ?.where((e) => e.enabled && e.hasDownloadProvider)
            .toList() ??
        [];
    if (!context.mounted) return;

    final choice = await showDownloadSheet(
      context,
      track: track,
      sources: sources,
    );
    if (!context.mounted) return;
    if (choice == null) return; // cancelled

    unawaited(
      queue
          .enqueue(track, service: choice.sourceId, quality: choice.quality)
          .catchError((Object _) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.downloadFailed)),
          );
        }
      }),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.downloadStarted)),
    );
  }

  // -------------------------------------------------------------------------
  // Batch download (selection mode)
  // -------------------------------------------------------------------------

  Future<void> _batchDownload(List<Track> allTracks) async {
    final t = AppLocalizations.of(context);
    final selected =
        allTracks.where((tr) => _selectedIds.contains(tr.id)).toList();
    if (selected.isEmpty) return;

    final sources = ref
            .read(extensionsProvider)
            .value
            ?.where((e) => e.enabled && e.hasDownloadProvider)
            .toList() ??
        [];
    if (!context.mounted) return;

    final choice = await showDownloadSheet(
      context,
      track: selected.first,
      sources: sources,
    );
    if (!context.mounted) return;
    if (choice == null) return; // user cancelled — nothing enqueued

    final queue = ref.read(downloadQueueProvider.notifier);
    for (final track in selected) {
      unawaited(queue.enqueue(
        track,
        service: choice.sourceId,
        quality: choice.quality,
      ));
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.batchAddedToQueue(selected.length))),
    );
    _exitSelectionMode();
  }

  Widget _buildFilterBar(AppLocalizations t) {
    final items = <(SearchFilter, String)>[
      (SearchFilter.all, t.filterAll),
      (SearchFilter.song, t.filterSong),
      (SearchFilter.artist, t.filterArtist),
      (SearchFilter.album, t.filterAlbum),
    ];
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final (f, label) in items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: FilterChip(
                label: Text(label),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final asyncExts = ref.watch(extensionsProvider);
    final enabledCount = asyncExts.when(
      data: (exts) => exts.where((e) => e.enabled).length,
      loading: () => 0,
      error: (e, st) => 0,
    );

    final AppBar appBar;
    if (_selectionMode && _selectedIds.isNotEmpty) {
      appBar = AppBar(
        automaticallyImplyLeading: false,
        title: Text(t.selectionCount(_selectedIds.length)),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: t.downloadCta,
            onPressed: () {
              final tracks = ref.read(searchProvider).value?.tracks ?? [];
              unawaited(_batchDownload(tracks));
            },
          ),
          IconButton(
            key: const Key('selectionClear'),
            icon: const Icon(Icons.close),
            tooltip: t.selectionClear,
            onPressed: _exitSelectionMode,
          ),
        ],
      );
    } else {
      appBar = AppBar(
        title: Text(t.tabSearch),
        // If we somehow ended up in selection mode with 0 selected, show close
        leading: _selectionMode
            ? IconButton(
                key: const Key('selectionClear'),
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              )
            : null,
      );
    }

    return Scaffold(
      appBar: appBar,
      body: Column(
        children: [
          // Banner: "using N sources" — accent-soft card with accent-line border
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: GestureDetector(
              onTap: () => context.go('/settings/sources'),
              child: Container(
                key: const Key('sourceBanner'),
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  border: Border.all(color: context.tokens.accentLine),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      t.sourcesInUse(enabledCount),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Search TextField
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: t.searchHint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (v) =>
                  ref.read(searchProvider.notifier).search(v),
              onChanged: (v) {
                setState(() => _queryEmpty = v.trim().isEmpty);
              },
            ),
          ),
          // Filter chips (All / Song / Artist / Album) — hidden in selection mode
          if (!_selectionMode) _buildFilterBar(t),
          // Results body
          Expanded(
            child: _SearchBody(
              filter: _filter,
              selectionMode: _selectionMode,
              selectedIds: _selectedIds,
              isQueryEmpty: _queryEmpty,
              onDownload: (ctx, track) =>
                  unawaited(_onDownload(ctx, track)),
              onLongPress: (trackId) => _enterSelectionMode(trackId),
              onSelectToggle: (trackId) => _toggleSelection(trackId),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBody extends ConsumerWidget {
  final SearchFilter filter;
  final bool selectionMode;
  final Set<String> selectedIds;
  final bool isQueryEmpty;
  final void Function(BuildContext context, Track track) onDownload;
  final void Function(String trackId) onLongPress;
  final void Function(String trackId) onSelectToggle;

  const _SearchBody({
    required this.filter,
    required this.selectionMode,
    required this.selectedIds,
    required this.isQueryEmpty,
    required this.onDownload,
    required this.onLongPress,
    required this.onSelectToggle,
  });

  Widget _existingEmptyState(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final enabled = ref.watch(extensionsProvider).maybeWhen(
          data: (x) => x.where((e) => e.enabled).length,
          orElse: () => 0,
        );
    return Center(
      child: Text(enabled == 0 ? t.searchNoSources : t.searchEmpty),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(downloadQueueProvider); // rebuild tiles when queue changes
    final t = AppLocalizations.of(context);

    if (isQueryEmpty) {
      final feed = ref.watch(homeFeedControllerProvider);
      return feed.when(
        data: (sections) => sections.isEmpty
            ? _existingEmptyState(context, ref)
            : ListView(
                children: [
                  for (final s in sections) ...[
                    _SectionHeader(title: s.title),
                    SizedBox(
                      height: 180,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: s.items.length,
                        itemBuilder: (_, i) => _HomeFeedCard(
                          item: s.items[i],
                          onDownload: onDownload,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _existingEmptyState(context, ref),
      );
    }

    return ref.watch(searchProvider).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text(t.searchError)),
      data: (results) {
        if (results.isEmpty) {
          return _existingEmptyState(context, ref);
        }

        // In selection mode only tracks are actionable; otherwise honour the
        // filter. "All" shows section headers; a single filter is a flat list.
        final showArtists = !selectionMode &&
            (filter == SearchFilter.all || filter == SearchFilter.artist) &&
            results.artists.isNotEmpty;
        final showAlbums = !selectionMode &&
            (filter == SearchFilter.all || filter == SearchFilter.album) &&
            results.albums.isNotEmpty;
        final showSongs = (selectionMode ||
                filter == SearchFilter.all ||
                filter == SearchFilter.song) &&
            results.tracks.isNotEmpty;
        final withHeaders = !selectionMode && filter == SearchFilter.all;

        // Section order: Songs → Albums → Artists.
        final children = <Widget>[];
        if (showSongs) {
          if (withHeaders) children.add(_SectionHeader(title: t.filterSong));
          for (final track in results.tracks) {
            children.add(TrackTile(
              track: track,
              qualityHint: track.qualityBadge,
              selectionMode: selectionMode,
              selected: selectedIds.contains(track.id),
              onDownload: () => onDownload(context, track),
              onLongPress: () => onLongPress(track.id),
              onSelectToggle: () => onSelectToggle(track.id),
              // No artist/album links on track rows — the Albums/Artists
              // sections below are the place to open those pages.
              downloadState: ref
                  .read(downloadQueueProvider.notifier)
                  .stateForTrack(track.id),
            ));
          }
        }
        if (showAlbums) {
          if (withHeaders) children.add(_SectionHeader(title: t.filterAlbum));
          children.addAll(results.albums.map((a) => _AlbumCard(album: a)));
        }
        if (showArtists) {
          if (withHeaders) children.add(_SectionHeader(title: t.filterArtist));
          children.addAll(results.artists.map((a) => _ArtistCard(artist: a)));
        }

        if (children.isEmpty) {
          return Center(child: Text(t.searchEmpty));
        }
        return ListView(children: children);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Section header + artist/album result cards
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      );
}

class _ArtistCard extends StatelessWidget {
  const _ArtistCard({required this.artist});
  final SearchArtist artist;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: _EntityThumb(
        url: artist.imageUrl,
        circle: true,
        fallbackIcon: Icons.person,
      ),
      title: Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(AppLocalizations.of(context).filterArtist,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
      onTap: () => context.push(
        '/search/artist',
        extra: ArtistRouteArgs(
            id: artist.routeId, name: artist.name, coverUrl: artist.imageUrl),
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album});
  final SearchAlbum album;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = [
      if (album.artists.isNotEmpty) album.artists,
      if (album.year.isNotEmpty) album.year,
    ].join(' · ');
    return ListTile(
      leading: _EntityThumb(
        url: album.imageUrl,
        circle: false,
        fallbackIcon: Icons.album,
      ),
      title: Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(sub.isEmpty ? AppLocalizations.of(context).filterAlbum : sub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
      onTap: () => context.push(
        '/search/album',
        extra: AlbumRouteArgs(
            id: album.routeId,
            name: album.name,
            artist: album.artists,
            coverUrl: album.imageUrl),
      ),
    );
  }
}

class _HomeFeedCard extends StatelessWidget {
  const _HomeFeedCard({required this.item, required this.onDownload});
  final HomeFeedItem item;
  final void Function(BuildContext context, Track track) onDownload;

  void _onTap(BuildContext context) {
    switch (item.type) {
      case 'track':
        onDownload(context, item.toTrack());
        break;
      case 'album':
        context.push(
          '/search/album',
          extra: AlbumRouteArgs(
              id: item.routeId,
              name: item.name,
              artist: item.artists,
              coverUrl: item.coverUrl),
        );
        break;
      case 'artist':
        context.push(
          '/search/artist',
          extra: ArtistRouteArgs(
              id: item.routeId, name: item.name, coverUrl: item.coverUrl),
        );
        break;
      case 'playlist':
        // Reuse the album screen's tracklist UI, resolved as a playlist.
        context.push(
          '/search/album',
          extra: AlbumRouteArgs(
              id: item.routeId,
              name: item.name,
              artist: item.artists,
              coverUrl: item.coverUrl,
              resourceType: 'playlist'),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _onTap(context),
      child: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: SizedBox(
          width: 120,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 120,
                  height: 120,
                  child: (item.coverUrl != null && item.coverUrl!.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: item.coverUrl!,
                          fit: BoxFit.cover,
                          memCacheWidth: 240,
                          memCacheHeight: 240,
                          placeholder: (_, _) =>
                              Container(color: context.tokens.surface3),
                          errorWidget: (_, _, _) =>
                              Container(color: context.tokens.surface3),
                        )
                      : Container(color: context.tokens.surface3),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntityThumb extends StatelessWidget {
  const _EntityThumb({
    required this.url,
    required this.circle,
    required this.fallbackIcon,
  });
  final String? url;
  final bool circle;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final radius = BorderRadius.circular(circle ? 24 : 8);
    final fallback = Container(
      width: 48,
      height: 48,
      color: tokens.surface3,
      child: Icon(fallbackIcon, color: cs.onSurfaceVariant, size: 24),
    );
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: 48,
        height: 48,
        child: (url != null && url!.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                memCacheWidth: 144,
                memCacheHeight: 144,
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
              )
            : fallback,
      ),
    );
  }
}

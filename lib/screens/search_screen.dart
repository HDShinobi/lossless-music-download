import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import '../models/installed_extension.dart';
import '../models/track.dart';
import '../providers/download_options_provider.dart';
import '../providers/download_queue_provider.dart';
import '../providers/extensions_provider.dart';
import '../providers/recent_searches_provider.dart';
import '../providers/search_provider.dart';
import '../screens/artist_screen.dart';
import '../screens/album_screen.dart';
import '../theme/app_tokens.dart';
import '../widgets/download_sheet.dart';
import '../widgets/track_tile.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  late final TextEditingController _ctrl;
  String? _sourceFilter; // null = all sources

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
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
  // Search
  // -------------------------------------------------------------------------

  void _search(String q) {
    final trimmed = q.trim();
    if (trimmed.isEmpty) return;
    _ctrl.text = trimmed;
    ref.read(searchProvider.notifier).search(trimmed);
    FocusScope.of(context).unfocus();
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

  // -------------------------------------------------------------------------
  // Batch download (selection mode)
  // -------------------------------------------------------------------------

  void _batchDownload(List<Track> allTracks) {
    final t = AppLocalizations.of(context);
    final queue = ref.read(downloadQueueProvider.notifier);
    final count = _selectedIds.length;

    for (final track in allTracks) {
      if (_selectedIds.contains(track.id)) {
        unawaited(queue.enqueue(track));
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.batchAddedToQueue(count))),
    );

    _exitSelectionMode();
  }

  // -------------------------------------------------------------------------
  // Navigation helpers
  // -------------------------------------------------------------------------

  void _openArtist(Track track) {
    if (track.artistId == null) return;
    context.push(
      '/search/artist',
      extra: ArtistRouteArgs(
        id: track.artistId!,
        name: track.artists,
        coverUrl: track.coverUrl,
      ),
    );
  }

  void _openAlbum(Track track) {
    if (track.albumId == null || track.albumName == null) return;
    context.push(
      '/search/album',
      extra: AlbumRouteArgs(
        id: track.albumId!,
        name: track.albumName!,
        artist: track.artists,
        coverUrl: track.coverUrl,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Row-tap: always show source+quality picker
  // -------------------------------------------------------------------------

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
    if (choice == null) return;

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
  // Source picker bottom sheet
  // -------------------------------------------------------------------------

  void _showSourcePicker(
    BuildContext context,
    List<InstalledExtension> exts,
  ) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.check,
                color: _sourceFilter == null ? cs.primary : Colors.transparent,
              ),
              title: Text(t.searchSourceAll),
              onTap: () {
                setState(() => _sourceFilter = null);
                Navigator.of(ctx).pop();
              },
            ),
            ...exts.map(
              (ext) => ListTile(
                leading: Icon(
                  Icons.check,
                  color: _sourceFilter == ext.id
                      ? cs.primary
                      : Colors.transparent,
                ),
                title: Text(ext.displayName),
                onTap: () {
                  setState(() => _sourceFilter = ext.id);
                  Navigator.of(ctx).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

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
              final tracks = ref.read(searchProvider).value ?? [];
              _batchDownload(tracks);
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
        leading: _selectionMode
            ? IconButton(
                key: const Key('selectionClear'),
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              )
            : null,
      );
    }

    final metaExts = ref.watch(extensionsProvider).maybeWhen(
          data: (exts) =>
              exts.where((e) => e.enabled && e.hasMetadataProvider).toList(),
          orElse: () => <InstalledExtension>[],
        );

    return Scaffold(
      appBar: appBar,
      body: Column(
        children: [
          // Search bar row: [Source pill] [TextField] [×]
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                _SourcePill(
                  label: _sourceFilter == null
                      ? t.searchSourceAll
                      : (metaExts
                              .where((e) => e.id == _sourceFilter)
                              .firstOrNull
                              ?.displayName ??
                          t.searchSourceAll),
                  onTap: () => _showSourcePicker(context, metaExts),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: InputDecoration(
                      hintText: t.searchHint,
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: _ctrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _ctrl.clear();
                                ref.read(searchProvider.notifier).search('');
                              },
                            )
                          : null,
                    ),
                    onSubmitted: _search,
                    textInputAction: TextInputAction.search,
                  ),
                ),
              ],
            ),
          ),

          // Results body or recent searches.
          // Show recent searches only when the field is empty AND no search
          // results have been loaded (initial state or explicitly cleared).
          Expanded(
            child: Builder(
              builder: (ctx) {
                final searchState = ref.watch(searchProvider);
                final hasNoResults = !searchState.isLoading &&
                    !searchState.hasError &&
                    (searchState.value?.isEmpty ?? true);
                if (_ctrl.text.isEmpty && hasNoResults) {
                  return _RecentSearchesSection(onSearch: _search);
                }
                return _SearchBody(
                  selectionMode: _selectionMode,
                  selectedIds: _selectedIds,
                  sourceFilter: _sourceFilter,
                  onDownload: (context, track) =>
                      unawaited(_onDownload(context, track)),
                  onRowTap: (context, track) =>
                      unawaited(_showPickerSheet(context, track)),
                  onLongPress: (trackId) => _enterSelectionMode(trackId),
                  onSelectToggle: (trackId) => _toggleSelection(trackId),
                  onArtistTap: _openArtist,
                  onAlbumTap: _openAlbum,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

}

// ---------------------------------------------------------------------------
// Source pill — compact button in the search bar row
// ---------------------------------------------------------------------------
class _SourcePill extends StatelessWidget {
  const _SourcePill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: tokens.surface2,
          border: Border.all(color: cs.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent searches section
// ---------------------------------------------------------------------------
class _RecentSearchesSection extends ConsumerWidget {
  const _RecentSearchesSection({required this.onSearch});

  final void Function(String query) onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final async = ref.watch(recentSearchesProvider);

    final enabledCount = ref.watch(extensionsProvider).maybeWhen(
          data: (exts) => exts.where((e) => e.enabled).length,
          orElse: () => 0,
        );
    final recent = async.value ?? [];
    if (recent.isEmpty) {
      return Center(
        child: Text(enabledCount == 0 ? t.searchNoSources : t.searchEmpty),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                t.recentSearches,
                style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(recentSearchesProvider.notifier).clear(),
                child: Text(t.recentSearchesClear, style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: recent.length,
            itemBuilder: (ctx, i) {
              final q = recent[i];
              return ListTile(
                dense: true,
                leading: Icon(
                  Icons.history,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                title: Text(q, style: tt.bodyMedium),
                trailing: IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                  onPressed: () =>
                      ref.read(recentSearchesProvider.notifier).remove(q),
                ),
                onTap: () => onSearch(q),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Search results body
// ---------------------------------------------------------------------------
class _SearchBody extends ConsumerWidget {
  final bool selectionMode;
  final Set<String> selectedIds;
  final String? sourceFilter;
  final void Function(BuildContext context, Track track) onDownload;
  final void Function(BuildContext context, Track track) onRowTap;
  final void Function(String trackId) onLongPress;
  final void Function(String trackId) onSelectToggle;
  final void Function(Track track) onArtistTap;
  final void Function(Track track) onAlbumTap;

  const _SearchBody({
    required this.selectionMode,
    required this.selectedIds,
    required this.sourceFilter,
    required this.onDownload,
    required this.onRowTap,
    required this.onLongPress,
    required this.onSelectToggle,
    required this.onArtistTap,
    required this.onAlbumTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final async = ref.watch(searchProvider);

    Widget body;
    if (async.isLoading) {
      body = const _SearchSkeleton(key: ValueKey('loading'));
    } else if (async.hasError) {
      body = Center(key: const ValueKey('error'), child: Text(t.searchError));
    } else {
      final allTracks = async.value ?? [];
      final tracks = sourceFilter == null
          ? allTracks
          : allTracks.where((t) => t.source == sourceFilter).toList();

      if (tracks.isEmpty) {
        final enabled = ref.watch(extensionsProvider).maybeWhen(
              data: (x) => x.where((e) => e.enabled).length,
              orElse: () => 0,
            );
        body = Center(
          key: const ValueKey('empty'),
          child: Text(enabled == 0 ? t.searchNoSources : t.searchEmpty),
        );
      } else {
        body = ListView.builder(
          key: const ValueKey('results'),
          itemCount: tracks.length,
          itemBuilder: (context, index) {
            final track = tracks[index];
            return _StaggerItem(
              index: index,
              child: TrackTile(
                track: track,
                qualityHint: track.qualityBadge,
                selectionMode: selectionMode,
                selected: selectedIds.contains(track.id),
                onDownload: () => onDownload(context, track),
                onRowTap: () => onRowTap(context, track),
                onLongPress: () => onLongPress(track.id),
                onSelectToggle: () => onSelectToggle(track.id),
                onArtistTap: track.artistId != null
                    ? () => onArtistTap(track)
                    : null,
                onAlbumTap: track.albumId != null
                    ? () => onAlbumTap(track)
                    : null,
              ),
            );
          },
        );
      }
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: body,
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton shimmer — shown while search is in flight
// ---------------------------------------------------------------------------
class _SearchSkeleton extends StatefulWidget {
  const _SearchSkeleton({super.key});

  @override
  State<_SearchSkeleton> createState() => _SearchSkeletonState();
}

class _SearchSkeletonState extends State<_SearchSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) => ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 8,
        itemBuilder: (context, i) => Opacity(
          opacity: _anim.value,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: tokens.surface3,
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 13,
                        decoration: BoxDecoration(
                          color: tokens.surface3,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        height: 11,
                        width: 160,
                        decoration: BoxDecoration(
                          color: tokens.surface2,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stagger animation — fade-in + slide-up per list item
// ---------------------------------------------------------------------------
class _StaggerItem extends StatefulWidget {
  final int index;
  final Widget child;

  const _StaggerItem({required this.index, required this.child});

  @override
  State<_StaggerItem> createState() => _StaggerItemState();
}

class _StaggerItemState extends State<_StaggerItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    final delay = Duration(milliseconds: 28 * widget.index.clamp(0, 8));
    Future.delayed(delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => FadeTransition(
        opacity: _opacity,
        child: SlideTransition(position: _slide, child: child),
      ),
      child: widget.child,
    );
  }
}

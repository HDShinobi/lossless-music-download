import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import '../models/track.dart';
import '../providers/download_options_provider.dart';
import '../providers/download_queue_provider.dart';
import '../providers/extensions_provider.dart';
import '../providers/search_provider.dart';
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
    final t = AppLocalizations.of(context);
    final queue = ref.read(downloadQueueProvider.notifier);
    final askBefore = ref.read(askBeforeDownloadProvider);

    if (!askBefore) {
      unawaited(
        queue.enqueue(track).catchError((Object _) {
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
      return;
    }

    // askBefore == true: show source/quality sheet
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
          .enqueue(track, source: choice.sourceId, quality: choice.quality)
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
              decoration: InputDecoration(
                hintText: t.searchHint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (v) =>
                  ref.read(searchProvider.notifier).search(v),
            ),
          ),
          // Results body
          Expanded(
            child: _SearchBody(
              selectionMode: _selectionMode,
              selectedIds: _selectedIds,
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
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(BuildContext context, Track track) onDownload;
  final void Function(String trackId) onLongPress;
  final void Function(String trackId) onSelectToggle;

  const _SearchBody({
    required this.selectionMode,
    required this.selectedIds,
    required this.onDownload,
    required this.onLongPress,
    required this.onSelectToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return ref.watch(searchProvider).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text(t.searchError)),
      data: (tracks) {
        if (tracks.isEmpty) {
          final enabled = ref.watch(extensionsProvider).maybeWhen(
                data: (x) => x.where((e) => e.enabled).length,
                orElse: () => 0,
              );
          return Center(
            child: Text(
              enabled == 0 ? t.searchNoSources : t.searchEmpty,
            ),
          );
        }
        return ListView.builder(
          itemCount: tracks.length,
          itemBuilder: (context, index) {
            final track = tracks[index];
            return TrackTile(
              track: track,
              qualityHint: null,
              selectionMode: selectionMode,
              selected: selectedIds.contains(track.id),
              onDownload: () => onDownload(context, track),
              onLongPress: () => onLongPress(track.id),
              onSelectToggle: () => onSelectToggle(track.id),
            );
          },
        );
      },
    );
  }
}

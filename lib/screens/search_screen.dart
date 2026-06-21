import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import '../models/track.dart';
import '../providers/download_options_provider.dart';
import '../providers/downloads_provider.dart';
import '../providers/extensions_provider.dart';
import '../providers/search_provider.dart';
import '../theme/app_tokens.dart';
import '../widgets/download_sheet.dart';
import '../widgets/track_tile.dart';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  Future<void> _onDownload(BuildContext context, WidgetRef ref, Track track) async {
    final t = AppLocalizations.of(context);
    final controller = ref.read(downloadControllerProvider);
    final askBefore = ref.read(askBeforeDownloadProvider);

    if (!askBefore) {
      unawaited(
        controller.start(track).catchError((Object _) {
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
      controller
          .start(track, source: choice.sourceId, quality: choice.quality)
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final asyncExts = ref.watch(extensionsProvider);
    final enabledCount = asyncExts.when(
      data: (exts) => exts.where((e) => e.enabled).length,
      loading: () => 0,
      error: (e, st) => 0,
    );

    return Scaffold(
      appBar: AppBar(title: Text(t.tabSearch)),
      body: Column(
        children: [
          // Banner: "dang dung N nguon" -- accent-soft card with accent-line border
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
              onDownload: (ctx, track) => unawaited(_onDownload(ctx, ref, track)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBody extends ConsumerWidget {
  final void Function(BuildContext context, Track track) onDownload;
  const _SearchBody({required this.onDownload});

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
              onDownload: () => onDownload(context, track),
            );
          },
        );
      },
    );
  }
}

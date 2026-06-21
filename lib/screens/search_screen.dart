import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import '../models/track.dart';
import '../providers/downloads_provider.dart';
import '../providers/extensions_provider.dart';
import '../providers/search_provider.dart';
import '../theme/app_tokens.dart';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  void _onDownload(BuildContext context, WidgetRef ref, Track track) {
    final t = AppLocalizations.of(context);
    final controller = ref.read(downloadControllerProvider);
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
              onDownload: (ctx, track) => _onDownload(ctx, ref, track),
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
            return ListTile(
              leading: SizedBox(
                width: 48,
                height: 48,
                child: track.coverUrl != null
                    ? Image.network(
                        track.coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, trace) =>
                            const Icon(Icons.music_note),
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          );
                        },
                      )
                    : const Icon(Icons.music_note),
              ),
              title: Text(track.name),
              subtitle: Text(track.artists),
              trailing: IconButton(
                icon: const Icon(Icons.download_outlined),
                tooltip: t.download,
                onPressed: () => onDownload(context, track),
              ),
            );
          },
        );
      },
    );
  }
}

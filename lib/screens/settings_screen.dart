import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import '../providers/download_dir_provider.dart';
import '../providers/download_options_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final askBefore = ref.watch(askBeforeDownloadProvider);
    final embedMeta = ref.watch(embedMetadataProvider);
    final embedCover = ref.watch(embedCoverProvider);
    final embedLyrics = ref.watch(embedLyricsProvider);
    final folderAsync = ref.watch(downloadDirProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.tabSettings)),
      body: ListView(
        children: [
          // Sources
          ListTile(
            leading: const Icon(Icons.extension_outlined),
            title: Text(t.sourcesTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/sources'),
          ),

          const Divider(height: 1),

          // Download folder (read-only display)
          folderAsync.when(
            loading: () => ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(t.settingDownloadFolder),
              subtitle: const Text('…'),
            ),
            error: (_, __) => ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(t.settingDownloadFolder),
            ),
            data: (path) => ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(t.settingDownloadFolder),
              subtitle: Text(
                path,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ),

          // Ask before download
          SwitchListTile(
            secondary: const Icon(Icons.tune_outlined),
            title: Text(t.settingAskBeforeDownload),
            subtitle: Text(t.settingAskBeforeDownloadDesc),
            value: askBefore,
            onChanged: (v) =>
                ref.read(askBeforeDownloadProvider.notifier).set(v),
          ),

          const Divider(height: 1),

          // Embed metadata
          SwitchListTile(
            secondary: const Icon(Icons.tag),
            title: Text(t.settingEmbedMetadata),
            subtitle: Text(t.settingEmbedMetadataDesc),
            value: embedMeta,
            onChanged: (v) =>
                ref.read(embedMetadataProvider.notifier).set(v),
          ),

          // Embed cover art
          SwitchListTile(
            secondary: const Icon(Icons.image_outlined),
            title: Text(t.settingEmbedCover),
            subtitle: Text(t.settingEmbedCoverDesc),
            value: embedCover,
            onChanged: (v) =>
                ref.read(embedCoverProvider.notifier).set(v),
          ),

          // Embed lyrics
          SwitchListTile(
            secondary: const Icon(Icons.lyrics_outlined),
            title: Text(t.settingEmbedLyrics),
            subtitle: Text(t.settingEmbedLyricsDesc),
            value: embedLyrics,
            onChanged: (v) =>
                ref.read(embedLyricsProvider.notifier).set(v),
          ),
        ],
      ),
    );
  }
}

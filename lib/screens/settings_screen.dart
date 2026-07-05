import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/download_dir_provider.dart';
import '../providers/download_options_provider.dart';
import '../services/update_checker.dart';
import '../widgets/update_dialog.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  /// Manually checks GitHub for a newer release: shows the update dialog if one
  /// exists, otherwise a brief "up to date" confirmation.
  Future<void> _checkForUpdates(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(t.updateChecking)));
    final info = await UpdateChecker().checkForUpdate();
    if (!context.mounted) return;
    if (info == null) {
      messenger.showSnackBar(SnackBar(content: Text(t.updateUpToDate)));
      return;
    }
    await showUpdateDialog(context, info);
  }

  /// Requests the right storage permission for the OS version (legacy storage
  /// on Android 9–10, All-Files-Access on 11+), opens the system directory
  /// picker, and persists the chosen real filesystem path as the download
  /// folder. No-ops if the user cancels or denies permission.
  Future<void> _pickDownloadFolder(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (Platform.isAndroid) {
      // MANAGE_EXTERNAL_STORAGE ("All files access") only exists on Android 11+
      // (API 30). On 9–10 we must request the legacy WRITE_EXTERNAL_STORAGE
      // runtime permission instead, otherwise the request never resolves and
      // the picker keeps asking forever.
      final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      final permission =
          sdkInt >= 30 ? Permission.manageExternalStorage : Permission.storage;

      var status = await permission.status;
      if (!status.isGranted) {
        status = await permission.request();
      }
      if (!status.isGranted) {
        if (!context.mounted) return;
        final open = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(t.settingStoragePermissionTitle),
            content: Text(t.settingStoragePermissionBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(t.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(t.settingStoragePermissionOpen),
              ),
            ],
          ),
        );
        if (open == true) await openAppSettings();
        return;
      }
    }

    final picked = await FilePicker.platform.getDirectoryPath();
    if (picked == null || picked.isEmpty) return; // cancelled
    final path = normalizePickedDirectory(picked);
    if (path == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(t.settingStoragePermissionBody)),
      );
      return;
    }
    await ref.read(downloadDirControllerProvider.notifier).setDirectory(path);
    messenger.showSnackBar(
      SnackBar(content: Text(t.settingDownloadFolderUpdated)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final askBefore = ref.watch(askBeforeDownloadProvider);
    final embedMeta = ref.watch(embedMetadataProvider);
    final embedCover = ref.watch(embedCoverProvider);
    final embedLyrics = ref.watch(embedLyricsProvider);
    final writeLrcSidecar = ref.watch(writeLrcSidecarProvider);
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

          // Fallback sources
          ListTile(
            leading: const Icon(Icons.swap_horiz_outlined),
            title: Text(t.fallbackSourcesTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/fallback-sources'),
          ),

          // Check for app updates (GitHub Releases)
          ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: Text(t.settingCheckUpdate),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _checkForUpdates(context),
          ),

          const Divider(height: 1),

          // Download folder (tap to change)
          folderAsync.when(
            loading: () => ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(t.settingDownloadFolder),
              subtitle: const Text('…'),
            ),
            error: (_, _) => ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(t.settingDownloadFolder),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _pickDownloadFolder(context, ref),
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
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _pickDownloadFolder(context, ref),
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

          // Write .lrc lyrics sidecar
          SwitchListTile(
            secondary: const Icon(Icons.subtitles_outlined),
            title: Text(t.lrcSidecarTitle),
            subtitle: Text(t.lrcSidecarSubtitle),
            value: writeLrcSidecar,
            onChanged: (v) =>
                ref.read(writeLrcSidecarProvider.notifier).set(v),
          ),
        ],
      ),
    );
  }
}

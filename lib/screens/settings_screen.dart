import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import '../providers/download_options_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final askBefore = ref.watch(askBeforeDownloadProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.tabSettings)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.extension_outlined),
            title: Text(t.sourcesTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/sources'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.tune_outlined),
            title: Text(t.settingAskBeforeDownload),
            subtitle: Text(t.settingAskBeforeDownloadDesc),
            value: askBefore,
            onChanged: (v) =>
                ref.read(askBeforeDownloadProvider.notifier).set(v),
          ),
        ],
      ),
    );
  }
}

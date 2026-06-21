import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
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
        ],
      ),
    );
  }
}

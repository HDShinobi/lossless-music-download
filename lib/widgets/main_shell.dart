import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.shell});
  final StatefulNavigationShell shell;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.search), label: t.tabSearch),
          NavigationDestination(
              icon: const Icon(Icons.download_outlined), label: t.tabQueue),
          NavigationDestination(
              icon: const Icon(Icons.wifi_tethering), label: t.tabServer),
          NavigationDestination(
              icon: const Icon(Icons.library_music_outlined),
              label: t.tabLibrary),
          NavigationDestination(
              icon: const Icon(Icons.settings_outlined), label: t.tabSettings),
        ],
      ),
    );
  }
}

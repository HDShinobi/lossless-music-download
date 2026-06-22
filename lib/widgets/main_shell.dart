import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../providers/search_provider.dart';
import '../vendor/spotiflac/share_intent_service.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  StreamSubscription<String>? _shareSub;

  @override
  void initState() {
    super.initState();
    final svc = ShareIntentService();
    svc.initialize().then((_) {
      if (!mounted) return;
      final pending = svc.consumePendingUrl();
      if (pending != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _handleSharedUrl(pending);
        });
      }
    });
    _shareSub = ShareIntentService().sharedUrlStream.listen((url) {
      if (mounted) _handleSharedUrl(url);
    });
  }

  void _handleSharedUrl(String url) {
    widget.shell.goBranch(0, initialLocation: widget.shell.currentIndex == 0);
    ref.read(searchProvider.notifier).resolveFromUrl(url);
    if (!context.mounted) return;
    final t = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.loadingSharedLink)),
    );
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      body: widget.shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.shell.currentIndex,
        onDestinationSelected: (i) =>
            widget.shell.goBranch(i, initialLocation: i == widget.shell.currentIndex),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.search), label: t.tabSearch),
          NavigationDestination(icon: const Icon(Icons.download_outlined), label: t.tabQueue),
          NavigationDestination(icon: const Icon(Icons.wifi_tethering), label: t.tabServer),
          NavigationDestination(icon: const Icon(Icons.library_music_outlined), label: t.tabLibrary),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), label: t.tabSettings),
        ],
      ),
    );
  }
}

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
  String? _handledInitialUrl;

  @override
  void initState() {
    super.initState();
    final svc = ShareIntentService();
    svc.initialize().then((_) {
      if (!mounted) return;
      final pending = svc.consumePendingUrl();
      if (pending != null) {
        _handledInitialUrl = pending;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _handleSharedUrl(pending);
        });
      }
    });
    _shareSub = svc.sharedUrlStream.listen((url) {
      if (!mounted) return;
      if (url == _handledInitialUrl) {
        _handledInitialUrl = null;
        return; // skip: already handled as pending URL
      }
      _handleSharedUrl(url);
    });
  }

  Future<void> _handleSharedUrl(String url) async {
    widget.shell.goBranch(0, initialLocation: widget.shell.currentIndex == 0);
    if (!context.mounted) return;
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(t.loadingSharedLink)));
    await ref.read(searchProvider.notifier).resolveFromUrl(url);
    if (!mounted) return;
    final tracks = ref.read(searchProvider).value;
    if (tracks != null && tracks.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(t.shareUrlNotRecognized)));
    }
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

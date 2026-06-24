import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../providers/download_queue_provider.dart';
import '../providers/search_provider.dart';
import '../theme/app_tokens.dart';
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
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DownloadBar(onTap: () => widget.shell.goBranch(2)),
          NavigationBar(
            selectedIndex: widget.shell.currentIndex,
            onDestinationSelected: (i) =>
                widget.shell.goBranch(i, initialLocation: i == widget.shell.currentIndex),
            destinations: [
              NavigationDestination(icon: const Icon(Icons.search), label: t.tabSearch),
              NavigationDestination(icon: const Icon(Icons.library_music_outlined), label: t.tabLibrary),
              NavigationDestination(icon: const Icon(Icons.download_outlined), label: t.tabQueue),
              NavigationDestination(icon: const Icon(Icons.wifi_tethering), label: t.tabServer),
              NavigationDestination(icon: const Icon(Icons.settings_outlined), label: t.tabSettings),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Persistent download activity bar — shows above nav when a download is active
// ---------------------------------------------------------------------------

class _DownloadBar extends ConsumerWidget {
  const _DownloadBar({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(downloadQueueProvider);
    final active = entries.where((e) =>
        e.status == 'downloading' || e.status == 'finalizing').toList();
    final queued = entries.where((e) => e.status == 'queued').length;

    if (active.isEmpty && queued == 0) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final current = active.isNotEmpty ? active.first : entries.first;
    final progress = current.progress.clamp(0.0, 1.0);
    final isDownloading = current.status == 'downloading';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: cs.surfaceContainerLow,
        child: Stack(
          children: [
            // progress fill
            if (progress > 0)
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(color: tokens.accentSoft),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: isDownloading
                        ? CircularProgressIndicator(
                            strokeWidth: 1.5,
                            value: progress > 0 ? progress : null,
                            color: cs.primary,
                          )
                        : Icon(Icons.schedule,
                            size: 14, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      current.track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                  if (queued > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '+$queued',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right, size: 16, color: tokens.muted2),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

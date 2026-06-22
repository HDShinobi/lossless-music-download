import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import 'package:lossless_music_download/models/server_status.dart';
import 'package:lossless_music_download/providers/download_dir_provider.dart';
import 'package:lossless_music_download/providers/server_provider.dart';
import 'package:lossless_music_download/theme/app_tokens.dart';

class ServerScreen extends ConsumerWidget {
  const ServerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final serverAsync = ref.watch(serverProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.tabServer)),
      body: serverAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  error.toString(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          ),
        ),
        data: (status) => _ServerBody(status: status),
      ),
    );
  }
}

class _ServerBody extends ConsumerWidget {
  const _ServerBody({required this.status});

  final ServerStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final tokens = context.tokens;
    final serverAsync = ref.watch(serverProvider);
    final bool running = status.running;
    final String? url = status.url;

    final downloadDirAsync = ref.watch(downloadDirProvider);
    final String folderPath = downloadDirAsync.value ?? '';

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status card
          Container(
            decoration: BoxDecoration(
              color: running ? tokens.accentSoft : null,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: running ? tokens.accentLine : tokens.muted2,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: running ? tokens.accentLine : tokens.muted2,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  running ? t.serverRunning : t.serverStopped,
                  style: TextStyle(
                    color: running
                        ? Theme.of(context).colorScheme.primary
                        : tokens.muted2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          if (running && url != null) ...[
            const SizedBox(height: 20),

            // Address row
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  t.serverAddress,
                  style: TextStyle(color: tokens.muted2, fontSize: 13),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    url,
                    style: tokens.mono.copyWith(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(t.serverCopied)),
                    );
                  },
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Folder row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.serverFolder,
                  style: TextStyle(color: tokens.muted2, fontSize: 13),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    folderPath,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ],

          const Spacer(),

          // Start / Stop button
          FilledButton(
            onPressed: serverAsync.isLoading
                ? null
                : () {
                    if (running) {
                      ref.read(serverProvider.notifier).stop();
                    } else {
                      ref.read(serverProvider.notifier).start();
                    }
                  },
            child: serverAsync.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(running ? t.serverStop : t.serverStart),
          ),

          const SizedBox(height: 12),

          // Hint line
          Text(
            t.serverHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: tokens.muted2,
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

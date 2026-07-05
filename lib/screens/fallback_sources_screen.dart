import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import '../providers/extensions_provider.dart';
import '../providers/fallback_pool_provider.dart';

/// Lets the user pick which enabled download-capable sources participate in
/// automatic fallback. `null` in [fallbackPoolProvider] means "all"; toggling
/// a row recomputes the explicit checked-id list and persists it.
class FallbackSourcesScreen extends ConsumerWidget {
  const FallbackSourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final exts = (ref.watch(extensionsProvider).value ?? const [])
        .where((e) => e.enabled && e.hasDownloadProvider)
        .toList();
    final pool = ref.watch(fallbackPoolProvider); // null = all
    bool checked(String id) => pool == null || pool.contains(id);

    return Scaffold(
      appBar: AppBar(title: Text(t.fallbackSourcesTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              t.fallbackSourcesHeader,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final e in exts)
            CheckboxListTile(
              title: Text(e.displayName),
              value: checked(e.id),
              onChanged: (v) {
                final next = [
                  for (final x in exts)
                    if (x.id == e.id ? (v ?? false) : checked(x.id)) x.id
                ];
                ref.read(fallbackPoolProvider.notifier).set(next);
              },
            ),
        ],
      ),
    );
  }
}

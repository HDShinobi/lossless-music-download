import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import '../providers/extensions_provider.dart';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final asyncExts = ref.watch(extensionsProvider);
    final enabledCount = asyncExts.when(
      data: (exts) => exts.where((e) => e.enabled).length,
      loading: () => 0,
      error: (e, st) => 0,
    );

    return Scaffold(
      appBar: AppBar(title: Text(t.tabSearch)),
      body: Column(
        children: [
          GestureDetector(
            onTap: () => context.go('/settings/sources'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    t.sourcesInUse(enabledCount),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: Center(child: Text(t.comingSoon))),
        ],
      ),
    );
  }
}

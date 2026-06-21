import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import '../models/installed_extension.dart';
import '../providers/extensions_provider.dart';

class ExtensionDetailScreen extends ConsumerWidget {
  final String id;
  const ExtensionDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final asyncExts = ref.watch(extensionsProvider);

    return asyncExts.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(err.toString())),
      ),
      data: (exts) {
        final ext = exts.where((e) => e.id == id).cast<InstalledExtension?>().firstOrNull;
        if (ext == null) {
          return Scaffold(
            appBar: AppBar(title: Text(id)),
            body: Center(child: Text(t.extNotFound)),
          );
        }
        return _buildDetail(context, ref, t, ext);
      },
    );
  }

  Widget _buildDetail(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations t,
    InstalledExtension ext,
  ) {
    return Scaffold(
      appBar: AppBar(title: Text(ext.displayName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          _buildHeader(context, ext),
          const SizedBox(height: 24),
          // Permissions section
          _buildPermissionsSection(context, t, ext),
          const SizedBox(height: 32),
          // Remove button
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () async {
              await ref.read(extensionsProvider.notifier).remove(ext.id);
              if (context.mounted) {
                context.go('/settings/sources');
              }
            },
            child: Text(t.removeExtension),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, InstalledExtension ext) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 28,
              child: Text(
                ext.displayName.isNotEmpty
                    ? ext.displayName[0].toUpperCase()
                    : '?',
                style: const TextStyle(fontSize: 22),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ext.displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    'v${ext.version}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (ext.types.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: ext.types
                .map(
                  (type) => Chip(
                    label: Text(type),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
                .toList(),
          ),
        ],
        if (ext.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            ext.description,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }

  Widget _buildPermissionsSection(
    BuildContext context,
    AppLocalizations t,
    InstalledExtension ext,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.permissions,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        // Network permissions (domains from the permissions list)
        if (ext.permissions.isNotEmpty)
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(t.permNetwork),
                ),
                ...ext.permissions.map(
                  (domain) => Padding(
                    padding: const EdgeInsets.only(left: 56, right: 16, bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        domain,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Text(
            t.permNone,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

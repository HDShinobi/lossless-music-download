import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import '../providers/discover_provider.dart';
import '../providers/extension_updates_provider.dart';
import '../providers/extensions_provider.dart';
import '../widgets/discover_tab.dart';
import '../widgets/priority_tab.dart';

class SourcesScreen extends ConsumerStatefulWidget {
  const SourcesScreen({super.key});

  @override
  ConsumerState<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends ConsumerState<SourcesScreen> {
  int _selectedSegment = 0;
  bool _updating = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    // Watching this warms the catalog on screen open, so updates are detected
    // without the user visiting the Discover tab first.
    final updates = ref.watch(extensionUpdatesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.sourcesTitle)),
      body: Column(
        children: [
          if (updates.isNotEmpty) _updatesBanner(t, updates),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text(t.tabInstalled)),
                ButtonSegment(value: 1, label: Text(t.tabDiscover)),
                ButtonSegment(value: 2, label: Text(t.tabPriority)),
              ],
              selected: {_selectedSegment},
              onSelectionChanged: (s) => setState(() => _selectedSegment = s.first),
            ),
          ),
          Expanded(child: _buildBody(context, t, updates)),
        ],
      ),
    );
  }

  Widget _updatesBanner(AppLocalizations t, List<ExtensionUpdate> updates) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.system_update_alt, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              t.extensionUpdatesAvailable(updates.length),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          _updating
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : FilledButton(
                  onPressed: () => _runUpdate(t, updates),
                  child: Text(t.extensionUpdateAll),
                ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations t,
    List<ExtensionUpdate> updates,
  ) {
    if (_selectedSegment == 1) {
      return const DiscoverTab();
    }
    if (_selectedSegment == 2) {
      return const PriorityTab();
    }

    // Segment 0: Installed
    final updatesById = {for (final u in updates) u.id: u};
    final asyncExts = ref.watch(extensionsProvider);
    return asyncExts.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text(err.toString())),
      data: (exts) {
        if (exts.isEmpty) {
          return Center(child: Text(t.noExtensions));
        }
        return ListView.builder(
          itemCount: exts.length,
          itemBuilder: (context, i) {
            final ext = exts[i];
            final isHealthy =
                ext.status == 'active' || ext.status == 'ok';
            final healthColor = isHealthy ? Colors.green : Colors.amber;
            final subtitle = '${ext.types.join(' · ')} · v${ext.version}';
            final update = updatesById[ext.id];

            return ListTile(
              isThreeLine: update != null,
              leading: CircleAvatar(
                child: Text(
                  ext.displayName.isNotEmpty
                      ? ext.displayName[0].toUpperCase()
                      : '?',
                ),
              ),
              title: Row(
                children: [
                  Expanded(child: Text(ext.displayName)),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: healthColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(subtitle),
                  if (update != null) _updateRow(t, update),
                ],
              ),
              trailing: Switch(
                value: ext.enabled,
                onChanged: (v) =>
                    ref.read(extensionsProvider.notifier).setEnabled(ext.id, v),
              ),
              onTap: () => context.go('/settings/sources/${ext.id}'),
            );
          },
        );
      },
    );
  }

  Widget _updateRow(AppLocalizations t, ExtensionUpdate update) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fiber_new, size: 16, color: accent),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  t.extensionUpdateNote(update.toVersion),
                  style: TextStyle(color: accent, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _updating ? null : () => _runUpdate(t, [update]),
            icon: const Icon(Icons.system_update_alt, size: 16),
            label: Text(t.extensionUpdateTo(update.toVersion)),
          ),
        ),
      ],
    );
  }

  Future<void> _runUpdate(
    AppLocalizations t,
    List<ExtensionUpdate> updates,
  ) async {
    if (_updating || updates.isEmpty) return;
    setState(() => _updating = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(t.extensionUpdating)));
    try {
      await ref
          .read(discoverProvider.notifier)
          .updateAll(updates.map((u) => u.storeExt).toList());
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(t.extensionUpdated)));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(t.extensionUpdateFailed)));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import '../providers/extensions_provider.dart';

class SourcesScreen extends ConsumerStatefulWidget {
  const SourcesScreen({super.key});

  @override
  ConsumerState<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends ConsumerState<SourcesScreen> {
  int _selectedSegment = 0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(t.sourcesTitle)),
      body: Column(
        children: [
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
          Expanded(child: _buildBody(context, t)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations t) {
    if (_selectedSegment == 1 || _selectedSegment == 2) {
      return Center(child: Text(t.comingSoon));
    }

    // Segment 0: Installed
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

            return ListTile(
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
              subtitle: Text(subtitle),
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
}

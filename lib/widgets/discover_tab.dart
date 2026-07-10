import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lossless_music_download/l10n/app_localizations.dart';
import '../models/store_extension.dart';
import '../providers/discover_provider.dart';
import '../providers/extension_updates_provider.dart';
import '../providers/extensions_provider.dart';

/// The "Khám phá" (Discover) tab — shows the extension catalog from the
/// aggregator, with category filtering and per-item install actions.
class DiscoverTab extends ConsumerStatefulWidget {
  const DiscoverTab({super.key});

  @override
  ConsumerState<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends ConsumerState<DiscoverTab> {
  /// Currently selected category filter. Empty string means "All".
  String _selectedCategory = '';

  /// Tracks which extension IDs are currently being installed.
  final Set<String> _installing = {};

  static const _categories = ['', 'download', 'metadata', 'lyrics'];

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final aggregatorUrl = ref.watch(aggregatorUrlProvider);
    final discoverAsync = ref.watch(discoverProvider);
    final installedAsync = ref.watch(extensionsProvider);

    final installedIds = installedAsync.value
            ?.map((e) => e.id)
            .toSet() ??
        const <String>{};
    final updatesById = {
      for (final u in ref.watch(extensionUpdatesProvider)) u.id: u
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AggregatorRow(aggregatorUrl: aggregatorUrl),
        _CategoryFilterRow(
          categories: _categories,
          selected: _selectedCategory,
          onSelect: (cat) => setState(() => _selectedCategory = cat),
        ),
        Expanded(
          child: discoverAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Center(child: Text(t.discoverError)),
            data: (list) {
              final filtered = _selectedCategory.isEmpty
                  ? list
                  : list
                      .where((e) =>
                          e.category.toLowerCase() ==
                          _selectedCategory.toLowerCase())
                      .toList();

              if (filtered.isEmpty) {
                return Center(child: Text(t.discoverEmpty));
              }

              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, i) => _ExtensionTile(
                  ext: filtered[i],
                  isInstalled: installedIds.contains(filtered[i].id),
                  isInstalling: _installing.contains(filtered[i].id),
                  update: updatesById[filtered[i].id],
                  onInstall: () => _installExtension(context, t, filtered[i]),
                  onUpdate: () => _updateExtension(context, t, filtered[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  Future<void> _installExtension(
    BuildContext context,
    AppLocalizations t,
    StoreExtension ext,
  ) async {
    setState(() => _installing.add(ext.id));
    try {
      await ref.read(discoverProvider.notifier).install(ext);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.installFailed)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _installing.remove(ext.id));
      }
    }
  }

  Future<void> _updateExtension(
    BuildContext context,
    AppLocalizations t,
    StoreExtension ext,
  ) async {
    setState(() => _installing.add(ext.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(discoverProvider.notifier).updateExtension(ext);
      messenger.showSnackBar(SnackBar(content: Text(t.extensionUpdated)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(t.extensionUpdateFailed)));
    } finally {
      if (mounted) {
        setState(() => _installing.remove(ext.id));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Private sub-widgets
// ---------------------------------------------------------------------------

/// Top row showing the current aggregator host and a "Change" button.
class _AggregatorRow extends ConsumerWidget {
  const _AggregatorRow({required this.aggregatorUrl});

  final String aggregatorUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final host = _hostOf(aggregatorUrl);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${t.aggregatorSource}: $host',
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () => _showChangeDialog(context, ref, t, aggregatorUrl),
            child: Text(t.changeAggregator),
          ),
        ],
      ),
    );
  }

  static String _hostOf(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
  }

  Future<void> _showChangeDialog(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations t,
    String currentUrl,
  ) async {
    // The dialog owns its TextEditingController (see _ChangeAggregatorDialog),
    // so the controller is disposed with the dialog widget — not synchronously
    // after showDialog() returns, which raced the dismiss animation and threw
    // "A TextEditingController was used after being disposed".
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _ChangeAggregatorDialog(initialUrl: currentUrl),
    );

    final trimmed = result?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      final uri = Uri.tryParse(trimmed);
      if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).invalidUrl)),
          );
        }
        return;
      }
      await ref.read(discoverProvider.notifier).setAggregatorUrl(trimmed);
    }
  }
}

/// Horizontally scrollable filter-chip row.
class _CategoryFilterRow extends StatelessWidget {
  const _CategoryFilterRow({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: categories.map((cat) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(_label(t, cat)),
              selected: selected == cat,
              onSelected: (_) => onSelect(cat),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _label(AppLocalizations t, String cat) {
    switch (cat) {
      case '':
        return t.allCategories;
      case 'download':
        return t.catDownload;
      case 'metadata':
        return t.catMetadata;
      case 'lyrics':
        return t.catLyrics;
      default:
        return cat;
    }
  }
}

/// A single row in the catalog list.
class _ExtensionTile extends StatelessWidget {
  const _ExtensionTile({
    required this.ext,
    required this.isInstalled,
    required this.isInstalling,
    required this.onInstall,
    required this.onUpdate,
    this.update,
  });

  final StoreExtension ext;
  final bool isInstalled;
  final bool isInstalling;
  final ExtensionUpdate? update;
  final VoidCallback onInstall;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final subtitle = '${ext.category} · ${ext.sourceName} · v${ext.version}';

    Widget trailing;
    if (isInstalling) {
      trailing = TextButton(
        onPressed: null,
        child: Text(t.installing),
      );
    } else if (update != null) {
      trailing = FilledButton.tonal(
        onPressed: onUpdate,
        child: Text(t.extensionUpdateTo(update!.toVersion)),
      );
    } else if (isInstalled) {
      trailing = TextButton(
        onPressed: null,
        child: Text(t.installed),
      );
    } else {
      trailing = TextButton(
        onPressed: onInstall,
        child: Text(t.install),
      );
    }

    return ListTile(
      leading: ext.iconUrl != null
          ? CircleAvatar(
              backgroundImage: NetworkImage(ext.iconUrl!),
              onBackgroundImageError: (e, st) {},
            )
          : CircleAvatar(
              child: Text(
                ext.displayName.isNotEmpty
                    ? ext.displayName[0].toUpperCase()
                    : '?',
              ),
            ),
      title: Text(ext.displayName),
      subtitle: Text(subtitle),
      trailing: trailing,
    );
  }
}

/// Change-aggregator dialog content. Owns its [TextEditingController] and
/// disposes it in [State.dispose] — which Flutter calls only after the dialog's
/// exit animation finishes, avoiding the "used after disposed" race that
/// happened when the controller was disposed right after showDialog() returned.
/// Pops `null` on cancel, or the trimmed URL string on save.
class _ChangeAggregatorDialog extends StatefulWidget {
  const _ChangeAggregatorDialog({required this.initialUrl});

  final String initialUrl;

  @override
  State<_ChangeAggregatorDialog> createState() =>
      _ChangeAggregatorDialogState();
}

class _ChangeAggregatorDialogState extends State<_ChangeAggregatorDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialUrl);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.changeAggregatorTitle),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(hintText: t.aggregatorUrlHint),
        keyboardType: TextInputType.url,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(t.save),
        ),
      ],
    );
  }
}

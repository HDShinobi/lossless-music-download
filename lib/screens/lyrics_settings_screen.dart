import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../models/lyrics_settings.dart';
import '../providers/download_options_provider.dart';
import '../providers/extensions_provider.dart';
import '../providers/lyrics_settings_provider.dart';

class LyricsSettingsScreen extends ConsumerStatefulWidget {
  const LyricsSettingsScreen({super.key});

  @override
  ConsumerState<LyricsSettingsScreen> createState() =>
      _LyricsSettingsScreenState();
}

class _LyricsSettingsScreenState extends ConsumerState<LyricsSettingsScreen> {
  bool _saving = false;
  String? _language;

  Future<void> _apply(Future<void> Function() update) async {
    setState(() => _saving = true);
    try {
      await update();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).lyricsSettingsError),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lyrics = ref.watch(lyricsSettingsProvider);
    final embed = ref.watch(embedLyricsProvider);
    final sidecar = ref.watch(writeLrcSidecarProvider);
    final extensions = ref.watch(extensionsProvider).value ?? const [];
    final names = {
      ...LyricsSettings.providerNames,
      for (final extension in extensions)
        if (extension.enabled && extension.hasLyricsProvider)
          'extension:${extension.id.toLowerCase()}': extension.displayName,
    };
    return Scaffold(
      appBar: AppBar(title: Text(t.lyricsSettingsTitle)),
      body: lyrics.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(t.lyricsSettingsError)),
        data: (settings) {
          // Hidden/uninstalled extension selections remain persisted so reinstalling
          // an extension restores its place; only available providers are shown.
          final enabled = settings.effectiveProviders
              .where(names.containsKey)
              .toList();
          final disabled = names.keys
              .where((id) => !settings.effectiveProviders.contains(id))
              .toList();
          final controller = ref.read(lyricsSettingsProvider.notifier);
          return AbsorbPointer(
            absorbing: _saving,
            child: ListView(
              children: [
                ListTile(
                  title: Text(t.lyricsSaveMode),
                  subtitle: DropdownButton<String>(
                    key: const ValueKey('lyricsSaveMode'),
                    isExpanded: true,
                    value: embed
                        ? (sidecar ? 'both' : 'embed')
                        : (sidecar ? 'external' : 'off'),
                    items: [
                      for (final entry in {
                        'embed': t.lyricsModeEmbed,
                        'external': t.lyricsModeExternal,
                        'both': t.lyricsModeBoth,
                        'off': t.lyricsModeOff,
                      }.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (mode) {
                      if (mode == null) return;
                      _apply(() async {
                        await ref
                            .read(embedLyricsProvider.notifier)
                            .set(mode == 'embed' || mode == 'both');
                        await ref
                            .read(writeLrcSidecarProvider.notifier)
                            .set(mode == 'external' || mode == 'both');
                      });
                    },
                  ),
                ),
                const Divider(),
                ListTile(
                  title: Text(t.lyricsProviderOrder),
                  subtitle: Text(t.lyricsProviderOrderDescription),
                ),
                TextButton(
                  onPressed: () => _apply(() => controller.setProviders([])),
                  child: Text(t.lyricsEngineDefaults),
                ),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: enabled.length,
                  onReorder: (oldIndex, newIndex) {
                    // Reorder the complete saved order, retaining unavailable extensions.
                    final order = [...settings.effectiveProviders];
                    final moved = enabled[oldIndex];
                    if (newIndex > oldIndex) newIndex--;
                    final visible = [...enabled]..removeAt(oldIndex);
                    visible.insert(newIndex, moved);
                    var index = 0;
                    final reordered = [
                      for (final id in order)
                        names.containsKey(id) ? visible[index++] : id,
                    ];
                    _apply(() => controller.setProviders(reordered));
                  },
                  itemBuilder: (context, index) {
                    final id = enabled[index];
                    return SwitchListTile(
                      key: ValueKey(id),
                      title: Text(names[id]!),
                      value: true,
                      secondary: ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle),
                      ),
                      onChanged: enabled.length <= 1
                          ? null
                          : (_) => _apply(
                              () => controller.setProviders(
                                [...settings.effectiveProviders]..remove(id),
                              ),
                            ),
                    );
                  },
                ),
                for (final id in disabled)
                  SwitchListTile(
                    key: ValueKey(id),
                    title: Text(names[id]!),
                    value: false,
                    onChanged: (_) => _apply(
                      () => controller.setProviders([
                        ...settings.effectiveProviders,
                        id,
                      ]),
                    ),
                  ),
                const Divider(),
                for (final entry in {
                  'include_translation_netease': t.lyricsTranslation,
                  'include_romanization_netease': t.lyricsRomanization,
                  'multi_person_word_by_word': t.lyricsMultiPerson,
                  'apple_elrc_word_sync': t.lyricsAppleWordSync,
                }.entries)
                  SwitchListTile(
                    key: ValueKey(entry.key),
                    title: Text(entry.value),
                    value:
                        (settings.options[entry.key] ??
                                LyricsSettings.defaultOptions[entry.key])
                            as bool,
                    onChanged: (value) =>
                        _apply(() => controller.setOption(entry.key, value)),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextFormField(
                    initialValue:
                        (settings.options['musixmatch_language'] ?? '')
                            as String,
                    maxLength: 16,
                    decoration: InputDecoration(
                      labelText: t.lyricsMusixmatchLanguage,
                      helperText: t.lyricsLanguageHint,
                    ),
                    onChanged: (value) => _language = value,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (value) => _apply(
                      () => controller.setOption('musixmatch_language', value),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => _apply(
                        () => controller.setOption(
                          'musixmatch_language',
                          _language ??
                              settings.options['musixmatch_language'] ??
                              '',
                        ),
                      ),
                      child: Text(t.save),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

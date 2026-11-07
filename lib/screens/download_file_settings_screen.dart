import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/metadata_separators.dart';
import '../providers/download_options_provider.dart';
import '../services/download_templates.dart';

class DownloadFileSettingsScreen extends ConsumerWidget {
  const DownloadFileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final filename = ref.watch(filenameTemplateProvider);
    final folder = ref.watch(albumFolderTemplateProvider);
    final mode = ref.watch(artistTagModeProvider);
    final separators = ref.watch(metadataSeparatorsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.fileSettingsTitle)),
      body: ListView(
        children: [
          ListTile(
            title: Text(t.filenameTemplateTitle),
            subtitle: Text(filename.isEmpty ? t.templateDefault : filename),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => _TemplateEditor(
                folder: false,
                current: filename,
                onSave: ref.read(filenameTemplateProvider.notifier).set,
              ),
            ),
          ),
          ListTile(
            title: Text(t.albumFolderTemplateTitle),
            subtitle: Text(folder.isEmpty ? t.templateDefault : folder),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => _TemplateEditor(
                folder: true,
                current: folder,
                onSave: ref.read(albumFolderTemplateProvider.notifier).set,
              ),
            ),
          ),
          const Divider(),
          ListTile(
            title: Text(t.artistTagModeTitle),
            subtitle: Text(_artistModeLabel(t, mode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog<void>(
              context: context,
              builder: (ctx) => SimpleDialog(
                title: Text(t.artistTagModeTitle),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(t.artistTagModeDescription),
                  ),
                  RadioGroup<String>(
                    groupValue: mode,
                    onChanged: (value) {
                      if (value != null) {
                        ref.read(artistTagModeProvider.notifier).set(value);
                        Navigator.pop(ctx);
                      }
                    },
                    child: Column(
                      children: [
                        for (final value in artistTagModes)
                          RadioListTile<String>(
                            value: value,
                            title: Text(_artistModeLabel(t, value)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(t.metadataSeparatorsDescription),
          ),
          for (final field in MetadataSeparators.fields)
            ListTile(
              title: Text(_separatorLabel(t, field)),
              subtitle: Text(
                separators.toJson()[field]!.isEmpty
                    ? t.separatorOriginal
                    : '“${separators.toJson()[field]}”',
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => _SeparatorEditor(
                  title: _separatorLabel(t, field),
                  current: separators.toJson()[field]!,
                  onSave: (value) => ref
                      .read(metadataSeparatorsProvider.notifier)
                      .setField(field, value),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _artistModeLabel(AppLocalizations t, String mode) => switch (mode) {
  'split_vorbis' => t.artistTagSplitVorbis,
  'primary' => t.artistTagPrimary,
  _ => t.artistTagJoined,
};

String _separatorLabel(AppLocalizations t, String field) => switch (field) {
  'album_artist' => t.separatorAlbumArtist,
  'composer' => t.separatorComposer,
  'genre' => t.separatorGenre,
  _ => t.separatorArtist,
};

class _TemplateEditor extends ConsumerStatefulWidget {
  const _TemplateEditor({
    required this.folder,
    required this.current,
    required this.onSave,
  });
  final bool folder;
  final String current;
  final Future<void> Function(String) onSave;

  @override
  ConsumerState<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends ConsumerState<_TemplateEditor> {
  late final TextEditingController _text;
  late bool _default;

  @override
  void initState() {
    super.initState();
    _default = widget.current.isEmpty;
    _text = TextEditingController(text: widget.current);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final presets = widget.folder
        ? DownloadTemplates.folderPresets
        : DownloadTemplates.filenamePresets;
    final error = _default
        ? null
        : DownloadTemplates.validate(_text.text, folder: widget.folder);
    final choice = _default
        ? ''
        : presets.contains(_text.text)
        ? _text.text
        : '__custom';
    final filename = widget.folder
        ? ref.watch(filenameTemplateProvider)
        : _default
        ? ''
        : _text.text;
    final folder = widget.folder
        ? _default
              ? ''
              : _text.text
        : ref.watch(albumFolderTemplateProvider);
    String preview(bool multiDisc) {
      final track = DownloadTemplates.sample(multiDisc: multiDisc);
      final target = resolveDownloadTarget(
        '',
        track,
        mode: ref.watch(folderOrganizationProvider),
        filenameTemplate: filename,
        albumFolderTemplate: folder,
        quality: 'LOSSLESS',
      );
      return '${target.dir.replaceFirst(RegExp(r'^/'), '')}/'
              '${DownloadTemplates.preview(target.template, track, quality: 'LOSSLESS')}.flac'
          .replaceFirst(RegExp(r'^/'), '');
    }

    return AlertDialog(
      title: Text(
        widget.folder ? t.albumFolderTemplateTitle : t.filenameTemplateTitle,
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButton<String>(
                value: choice,
                isExpanded: true,
                items: [
                  DropdownMenuItem(value: '', child: Text(t.templateDefault)),
                  for (final preset in presets)
                    DropdownMenuItem(value: preset, child: Text(preset)),
                  DropdownMenuItem(
                    value: '__custom',
                    child: Text(t.templateCustom),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _default = value == '';
                  if (value != null) {
                    _text.text = value == '__custom' ? '' : value;
                  }
                }),
              ),
              TextField(
                controller: _text,
                decoration: InputDecoration(
                  labelText: t.templateCustom,
                  errorText: error == null
                      ? null
                      : switch (error) {
                          'placeholder' => t.templatePlaceholderError,
                          'path' => t.templatePathError,
                          _ => t.templateEmptyError,
                        },
                  errorMaxLines: 3,
                ),
                onChanged: (_) => setState(() => _default = false),
              ),
              const SizedBox(height: 12),
              Text(t.templatePlaceholders),
              Text(
                DownloadTemplates.placeholders.map((p) => '{$p}').join(', '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                t.templatePaddingHelp(
                  '{track:02}, {disc:02}, {playlist_position:03}',
                ),
              ),
              if (widget.folder) Text(t.templateFolderHelp),
              Text(t.templateDiscSafety),
              const SizedBox(height: 16),
              if (error == null) ...[
                Text(t.templatePreviewSingle),
                Text(preview(false)),
                const SizedBox(height: 8),
                Text(t.templatePreviewMulti),
                Text(preview(true)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.commonCancel),
        ),
        FilledButton(
          onPressed: error == null
              ? () async {
                  await widget.onSave(_default ? '' : _text.text);
                  if (context.mounted) Navigator.pop(context);
                }
              : null,
          child: Text(t.commonSave),
        ),
      ],
    );
  }
}

class _SeparatorEditor extends StatefulWidget {
  const _SeparatorEditor({
    required this.title,
    required this.current,
    required this.onSave,
  });
  final String title, current;
  final Future<void> Function(String) onSave;
  @override
  State<_SeparatorEditor> createState() => _SeparatorEditorState();
}

class _SeparatorEditorState extends State<_SeparatorEditor> {
  late final _text = TextEditingController(text: widget.current);
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final valid = MetadataSeparators.isValid(_text.text);
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final value in ['', ', ', '; ', ' / '])
                  ChoiceChip(
                    label: Text(
                      value.isEmpty ? t.separatorOriginal : '“$value”',
                    ),
                    selected: _text.text == value,
                    onSelected: (_) => setState(() => _text.text = value),
                  ),
              ],
            ),
            TextField(
              controller: _text,
              decoration: InputDecoration(
                labelText: t.templateCustom,
                errorText: valid ? null : t.separatorError,
              ),
              onChanged: (_) => setState(() {}),
            ),
            Text(t.metadataSeparatorsDescription),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.commonCancel),
        ),
        FilledButton(
          onPressed: valid
              ? () async {
                  await widget.onSave(_text.text);
                  if (context.mounted) Navigator.pop(context);
                }
              : null,
          child: Text(t.commonSave),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../providers/library_manager.dart';
import '../providers/library_provider.dart';

/// Shows the edit-metadata bottom sheet for [entry], prefilled from its current
/// tags. Returns the lowercase-keyed field map to write (via [buildEditFields]),
/// or null if cancelled.
Future<Map<String, String>?> showEditMetadataSheet(
  BuildContext context,
  LibraryEntry entry,
) {
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EditMetadataSheet(entry: entry),
  );
}

class _EditMetadataSheet extends StatefulWidget {
  const _EditMetadataSheet({required this.entry});
  final LibraryEntry entry;

  @override
  State<_EditMetadataSheet> createState() => _EditMetadataSheetState();
}

class _EditMetadataSheetState extends State<_EditMetadataSheet> {
  late final TextEditingController _title;
  late final TextEditingController _artist;
  late final TextEditingController _album;
  late final TextEditingController _albumArtist;
  late final TextEditingController _year;
  late final TextEditingController _genre;
  late final TextEditingController _track;

  String _displayName() {
    final e = widget.entry;
    final noExt = e.name.contains('.')
        ? e.name.substring(0, e.name.lastIndexOf('.'))
        : e.name;
    return noExt.replaceFirst(RegExp(r'^[0-9]+[\s.]\s*'), '');
  }

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _title = TextEditingController(text: e.title ?? _displayName());
    _artist = TextEditingController(text: e.artistName ?? '');
    _album = TextEditingController(text: e.albumName ?? '');
    _albumArtist = TextEditingController();
    _year = TextEditingController();
    _genre = TextEditingController();
    _track = TextEditingController();
  }

  @override
  void dispose() {
    for (final c in [_title, _artist, _album, _albumArtist, _year, _genre, _track]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      buildEditFields(
        title: _title.text,
        artist: _artist.text,
        album: _album.text,
        albumArtist: _albumArtist.text,
        year: _year.text,
        genre: _genre.text,
        trackNumber: _track.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.editSheetTitle,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _field(_title, t.editFieldTitle),
            _field(_artist, t.editFieldArtist),
            _field(_album, t.editFieldAlbum),
            _field(_albumArtist, t.editFieldAlbumArtist),
            Row(
              children: [
                Expanded(
                  child: _field(_year, t.editFieldYear,
                      keyboard: TextInputType.number),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(_track, t.editFieldTrack,
                      keyboard: TextInputType.number),
                ),
              ],
            ),
            _field(_genre, t.editFieldGenre),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(t.commonSave),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/services/download_paths.dart';
import 'package:lossless_music_download/services/download_templates.dart';

void main() {
  const track = Track(
    id: 'x',
    name: 'Song',
    artists: 'AC/DC',
    albumName: 'Album',
    releaseDate: '2026-11-07',
    trackNumber: 3,
    discNumber: 2,
    totalDiscs: 2,
  );

  test('rejects unknown, malformed, empty and unsafe templates', () {
    for (final value in [
      '',
      '  ',
      '{unknown}',
      '{title',
      '{{title}}',
      '{title}/x',
      r'{title}\x',
      '...',
      '{track:999999}',
    ]) {
      expect(DownloadTemplates.validate(value), isNotNull, reason: value);
    }
    for (final value in [
      '/absolute',
      '../{album}',
      '{artist}//{album}',
      r'C:\{album}',
      '{album}/..',
    ]) {
      expect(
        DownloadTemplates.validate(value, folder: true),
        isNotNull,
        reason: value,
      );
    }
    expect(
      DownloadTemplates.validate('{artist}/{album} ({year})', folder: true),
      isNull,
    );
  });

  test('preview renders padded numbers and adds multi-disc protection', () {
    final target = resolveDownloadTarget(
      '/dl',
      track,
      mode: FolderOrganization.artistAlbum,
      filenameTemplate: '{track:03}. {title}',
      albumFolderTemplate: '{artist}/{album} ({year})',
    );
    expect(target.dir, '/dl/AC DC/Album (2026)');
    expect(target.template, '{disc}-{track:03}. {title}');
    expect(DownloadTemplates.preview(target.template, track), '2-003. Song');
    expect(
      DownloadTemplates.preview('{disc:02}-{track}. {title}', track),
      '02-03. Song',
    );
    expect(stripTrackNumberPrefix('02-03. Song'), 'Song');
  });

  test('single disc does not gain a prefix and default remains unchanged', () {
    const single = Track(
      id: 's',
      name: 'Song',
      artists: 'Artist',
      albumName: 'Album',
      trackNumber: 1,
      discNumber: 1,
      totalDiscs: 1,
    );
    final target = resolveDownloadTarget(
      '/dl',
      single,
      mode: FolderOrganization.artistAlbum,
    );
    expect(target.dir, '/dl/Artist/Album');
    expect(target.template, '{track}. {title}');
    expect(DownloadTemplates.preview(target.template, single), '01. Song');
    final custom = resolveDownloadTarget(
      '/dl',
      single,
      mode: FolderOrganization.none,
      filenameTemplate: '{title}',
    );
    expect(custom.template, '{title}');
  });

  test('metadata slashes never introduce extra folder levels', () {
    final target = resolveDownloadTarget(
      '/dl',
      track,
      mode: FolderOrganization.none,
      albumFolderTemplate: '{artist}/{album}',
    );
    expect(target.dir, '/dl/AC DC/Album');
    expect(DownloadTemplates.preview('{title} [{isrc}]', track), 'Song');
  });
}

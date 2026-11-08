import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/models/library_entry.dart';
import 'package:lossless_music_download/models/metadata_separators.dart';
import 'package:lossless_music_download/services/backend_bridge.dart';
import 'package:lossless_music_download/services/ffmpeg_metadata_service.dart';
import 'package:lossless_music_download/services/library_re_enrich.dart';

class _Bridge extends BackendBridge {
  final requests = <Map<String, dynamic>>[];
  final edits = <Map<String, String>>[];
  @override
  Future<Map<String, dynamic>> editFileMetadata(
    String path,
    Map<String, String> fields,
  ) async {
    edits.add(fields);
    return {'method': 'native', 'success': true};
  }

  Map<String, dynamic> preview = {
    'method': 'preview',
    'success': true,
    'enriched_metadata': {
      'track_name': 'Fresh',
      'artist_name': 'Solo feat. Guest',
      'genre': 'Pop; Rock',
    },
  };
  @override
  Future<Map<String, dynamic>> reEnrichFile(
    Map<String, dynamic> request,
  ) async {
    requests.add(request);
    return request['preview_only'] == true
        ? preview
        : {'method': 'native', 'success': true, 'enriched_metadata': request};
  }
}

const _entry = LibraryEntry(
  path: '/song.flac',
  name: 'song.flac',
  sizeBytes: 0,
  format: 'FLAC',
  verified: true,
  isrc: 'USABC1234567',
  durationMs: 180000,
);
void main() {
  test('request preserves scanned release tags when providers omit them', () {
    final request = const ReEnrichOptions().request(
      const LibraryEntry(
        path: '/song.flac',
        name: '01. Song.flac',
        sizeBytes: 0,
        format: 'FLAC',
        verified: true,
        albumArtist: 'Album artist',
        totalTracks: 12,
        totalDiscs: 2,
        releaseDate: '2026',
        genre: 'Jazz',
        composer: 'Composer',
        label: 'Label',
        copyright: 'Copyright',
      ),
    );
    expect(request['track_name'], 'Song');
    expect(request['album_artist'], 'Album artist');
    expect(request['total_tracks'], 12);
    expect(request['total_discs'], 2);
    expect(request['release_date'], '2026');
    expect(request['genre'], 'Jazz');
    expect(request['composer'], 'Composer');
    expect(request['label'], 'Label');
    expect(request['copyright'], 'Copyright');
  });
  test(
    'primary credits and separators are applied before native write',
    () async {
      final bridge = _Bridge();
      await reEnrichLibraryEntry(
        bridge,
        _entry,
        const ReEnrichOptions(
          artistTagMode: 'primary',
          separators: MetadataSeparators(genre: ' / '),
        ),
      );
      final request = bridge.requests.last;
      expect(request['artist_name'], 'Solo');
      expect(request['genre'], 'Pop / Rock');
      expect(request['artist_tag_mode'], 'primary');
      expect(request['search_online'], false);
      expect(request['cover_max_dimension'], 0);
      expect(request['lyrics_mode'], 'embed');
      expect(request['isrc'], 'USABC1234567');
      expect(request['duration_ms'], 180000);
    },
  );
  test(
    'custom separator takes precedence over native Vorbis splitting',
    () async {
      final bridge = _Bridge()
        ..preview = {
          'method': 'preview',
          'success': true,
          'enriched_metadata': {'artist_name': 'A, B', 'album_artist': 'C, D'},
        };
      await reEnrichLibraryEntry(
        bridge,
        _entry,
        const ReEnrichOptions(
          artistTagMode: 'split_vorbis',
          separators: MetadataSeparators(artist: '; '),
        ),
      );
      expect(bridge.edits.single, {
        'artist': 'A; B',
        'artist_separator': '; ',
        'artist_tag_mode': 'split_vorbis',
      });
    },
  );
  test('invalid preview never dispatches a write', () async {
    final bridge = _Bridge()
      ..preview = {'method': 'error', 'error': 'no match'};
    await expectLater(
      reEnrichLibraryEntry(bridge, _entry, const ReEnrichOptions()),
      throwsStateError,
    );
    expect(bridge.requests, hasLength(1));
  });

  group('FFmpeg apply', () {
    late Directory dir;
    late String path;
    final originalRunner = FfmpegMetadataService.execRunner;
    setUp(() async {
      final root = Directory('${Directory.systemTemp.path}/codex-scratch');
      await root.create(recursive: true);
      dir = await root.createTemp('c2-ffmpeg-');
      path = '${dir.path}/song.mp3';
      await File(path).writeAsString('original');
    });
    tearDown(() async {
      FfmpegMetadataService.execRunner = originalRunner;
      await dir.delete(recursive: true);
    });
    test(
      'successful write preserves metadata and existing cover streams',
      () async {
        late List<String> args;
        FfmpegMetadataService.execRunner = (command) async {
          args = command;
          await File(command.last).writeAsString('updated');
          return true;
        };
        await applyReEnrichFfmpeg(
          path,
          {
            'metadata': {'TITLE': 'Fresh'},
          },
          'joined',
          const MetadataSeparators(),
        );
        expect(args.sublist(args.indexOf('-map'), args.indexOf('-map') + 4), [
          '-map',
          '0',
          '-map_metadata',
          '0',
        ]);
        expect(args, contains('title=Fresh'));
        expect(await File(path).readAsString(), 'updated');
        expect(await dir.list().length, 1);
      },
    );
    test('vanished source is not recreated by FFmpeg publication', () async {
      FfmpegMetadataService.execRunner = (args) async {
        await File(args.last).writeAsString('updated');
        await File(path).delete();
        return true;
      };
      await expectLater(applyReEnrichFfmpeg(path, {'metadata': {'TITLE': 'Fresh'}},
        'joined', const MetadataSeparators()), throwsStateError);
      expect(await File(path).exists(), isFalse);
      expect(await dir.list().length, 0);
    });
    test(
      'failure preserves original and removes staging and downloaded cover',
      () async {
        final cover = File('${dir.path}/cover.jpg');
        await cover.writeAsString('cover');
        FfmpegMetadataService.execRunner = (args) async {
          await File(args.last).writeAsString('partial');
          return false;
        };
        await expectLater(
          applyReEnrichFfmpeg(
            path,
            {
              'metadata': {'TITLE': 'Fresh'},
              'cover_path': cover.path,
            },
            'joined',
            const MetadataSeparators(),
          ),
          throwsStateError,
        );
        expect(await File(path).readAsString(), 'original');
        expect(await cover.exists(), false);
        expect(await dir.list().length, 1);
      },
    );
    test('Vorbis split artist mode emits each credit separately', () async {
      final opus = '${dir.path}/song.opus';
      await File(opus).writeAsString('original');
      late List<String> args;
      FfmpegMetadataService.execRunner = (command) async {
        args = command;
        await File(command.last).writeAsString('updated');
        return true;
      };
      await applyReEnrichFfmpeg(
        opus,
        {
          'metadata': {'ARTIST': 'A, B', 'ALBUMARTIST': 'C; D'},
        },
        'split_vorbis',
        const MetadataSeparators(),
      );
      expect(
        args,
        containsAll(['ARTIST=A', 'ARTIST=B', 'ALBUMARTIST=C', 'ALBUMARTIST=D']),
      );
    });
    test('external lyrics are written beside the final file', () async {
      await writeReEnrichSidecar(path, {
        'file_path': '${dir.path}/renamed.mp3',
        'write_external_lrc': true,
        'lyrics': '[00:01]Hello',
      });
      expect(
        await File('${dir.path}/renamed.lrc').readAsString(),
        '[00:01]Hello',
      );
      expect(await File('${dir.path}/song.lrc').exists(), false);
    });
  });
}

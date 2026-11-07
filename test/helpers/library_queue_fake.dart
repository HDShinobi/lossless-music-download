import 'package:lossless_music_download/models/track.dart';
import 'package:lossless_music_download/providers/download_queue_provider.dart';

class LibraryQueueFake extends DownloadQueueController {
  @override
  List<DownloadEntry> build() => [];

  void replace(List<DownloadEntry> entries) => state = entries;
}

DownloadEntry queueEntry(String status, {String? filePath}) => DownloadEntry(
  track: const Track(
    id: 'qobuz:1',
    name: 'Song',
    artists: 'A',
    albumName: 'Album',
  ),
  itemId: 'download',
  status: status,
  progress: 0,
  bytesReceived: 0,
  filePath: filePath,
);

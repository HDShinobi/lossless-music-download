import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';

// ---------------------------------------------------------------------------
// downloadLabelsProvider — maps item_id -> Track for the active downloads
// ---------------------------------------------------------------------------

class _DownloadLabelsNotifier extends Notifier<Map<String, Track>> {
  @override
  Map<String, Track> build() => {};

  void put(String itemId, Track track) {
    state = {...state, itemId: track};
  }
}

final downloadLabelsProvider =
    NotifierProvider<_DownloadLabelsNotifier, Map<String, Track>>(
  _DownloadLabelsNotifier.new,
);

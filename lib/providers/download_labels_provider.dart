import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../util/queue_view.dart';
import 'downloads_provider.dart';

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

// ---------------------------------------------------------------------------
// queueViewProvider — computed list of QueueItemView, updated each poll
// ---------------------------------------------------------------------------

class _QueueViewNotifier extends Notifier<List<QueueItemView>> {
  Map<String, Sample> _prev = {};

  @override
  List<QueueItemView> build() {
    // Listen to every new emission from the downloads stream provider.
    ref.listen<AsyncValue<List<dynamic>>>(downloadsProvider, (_, next) {
      next.whenData((items) {
        final labels = ref.read(downloadLabelsProvider);
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final result = computeQueueView(
          items: List.from(items),
          labels: labels,
          prev: _prev,
          nowMs: nowMs,
        );
        _prev = result.next;
        state = result.views;
      });
    });
    return [];
  }
}

final queueViewProvider =
    NotifierProvider<_QueueViewNotifier, List<QueueItemView>>(
  _QueueViewNotifier.new,
);

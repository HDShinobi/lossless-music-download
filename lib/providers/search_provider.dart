import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import 'extensions_provider.dart';

class SearchNotifier extends AsyncNotifier<List<Track>> {
  @override
  List<Track> build() => [];

  Future<void> search(String q) async {
    if (q.trim().isEmpty) {
      state = const AsyncData([]);
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(backendBridgeProvider).searchTracks(q.trim()),
    );
  }
}

final searchProvider =
    AsyncNotifierProvider<SearchNotifier, List<Track>>(SearchNotifier.new);

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/track.dart';
import '../providers/download_options_provider.dart';
import '../services/backend_bridge.dart';
import '../providers/download_queue_provider.dart';
import '../providers/extensions_provider.dart';
import '../theme/app_tokens.dart';
import '../widgets/download_sheet.dart';
import '../widgets/track_tile.dart';

// ---------------------------------------------------------------------------
// Route args — passed via GoRouter `extra`
// ---------------------------------------------------------------------------
class AlbumRouteArgs {
  const AlbumRouteArgs({
    required this.id,
    required this.name,
    required this.artist,
    this.coverUrl,
    this.resourceType = 'album',
  });
  final String id;
  final String name;
  final String artist;
  final String? coverUrl;

  /// 'album' (default) or 'playlist' — selects the metadata resource type and
  /// the Spotify URL path. A playlist shows the same tracklist UI as an album.
  final String resourceType;
}

// ---------------------------------------------------------------------------
// Result model
// ---------------------------------------------------------------------------
class AlbumData {
  const AlbumData({
    required this.name,
    required this.artist,
    this.coverUrl,
    required this.tracks,
  });
  final String name;
  final String artist;
  final String? coverUrl;
  final List<Track> tracks;
}

/// Builds [AlbumData] from a provider metadata result (the shape returned by
/// `getProviderMetadata(provider, 'album', id)`): a `track_list` (or `tracks`)
/// array plus an optional `album_info` map. Missing fields fall back to [args].
AlbumData albumFromProviderMetadata(
  Map<String, dynamic> result,
  AlbumRouteArgs args,
) {
  final info = result['album_info'] as Map<String, dynamic>? ?? const {};
  final rawTracks =
      (result['track_list'] ?? result['tracks']) as List? ?? const [];
  final tracks =
      rawTracks.whereType<Map<String, dynamic>>().map(Track.fromJson).toList();
  return AlbumData(
    name: result['name']?.toString() ?? info['name']?.toString() ?? args.name,
    artist: result['artists']?.toString() ??
        result['artist']?.toString() ??
        info['artists']?.toString() ??
        info['artist']?.toString() ??
        args.artist,
    coverUrl: result['cover_url']?.toString() ??
        result['images']?.toString() ??
        info['cover_url']?.toString() ??
        info['images']?.toString() ??
        args.coverUrl,
    tracks: tracks,
  );
}

/// Builds [AlbumData] from a Spotify `handleUrl` result. Only `album`/`playlist`
/// results carry a track list; anything else yields an empty track list.
AlbumData albumFromSpotifyResult(
  Map<String, dynamic> result,
  AlbumRouteArgs args,
) {
  final type = result['type']?.toString() ?? '';
  List<Track> tracks = [];
  if ((type == 'album' || type == 'playlist') && result['tracks'] is List) {
    tracks = (result['tracks'] as List)
        .whereType<Map<String, dynamic>>()
        .map(Track.fromJson)
        .toList();
  }
  return AlbumData(
    name: result['name']?.toString() ?? args.name,
    artist: result['artist']?.toString() ??
        result['artists']?.toString() ??
        args.artist,
    coverUrl: result['images']?.toString() ??
        result['cover_url']?.toString() ??
        args.coverUrl,
    tracks: tracks,
  );
}

// ---------------------------------------------------------------------------
// FutureProvider family — cached per album ID.
//
// A `provider:id` argument (e.g. "deezer:123") is resolved through the
// provider's metadata API, mirroring ArtistScreen. A bare id is treated as a
// Spotify album and resolved through handleUrl.
// ---------------------------------------------------------------------------
/// Resolves an album/playlist's tracks. A `provider:id` argument goes through
/// the provider's metadata API for [AlbumRouteArgs.resourceType] ('album' or
/// 'playlist'); a bare id is treated as a Spotify resource of that type and
/// resolved via handleUrl. Extracted for testability.
Future<AlbumData> resolveAlbumData(
  BackendBridge bridge,
  AlbumRouteArgs args,
) async {
  final fallback = AlbumData(
    name: args.name,
    artist: args.artist,
    coverUrl: args.coverUrl,
    tracks: const [],
  );
  final type = args.resourceType;

  final colon = args.id.indexOf(':');
  if (colon > 0) {
    final provider = args.id.substring(0, colon);
    final rawId = args.id.substring(colon + 1);
    final result = await bridge.getProviderMetadata(provider, type, rawId);
    return result == null ? fallback : albumFromProviderMetadata(result, args);
  }

  final result =
      await bridge.handleUrl('https://open.spotify.com/$type/${args.id}');
  return result == null ? fallback : albumFromSpotifyResult(result, args);
}

final _albumDataProvider =
    FutureProvider.family<AlbumData, AlbumRouteArgs>((ref, args) =>
        resolveAlbumData(ref.read(backendBridgeProvider), args));

// ---------------------------------------------------------------------------
// AlbumScreen
// ---------------------------------------------------------------------------
class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({super.key, required this.args});

  final AlbumRouteArgs args;

  Future<void> _onDownload(
    BuildContext context,
    WidgetRef ref,
    Track track,
  ) async {
    final askBefore = ref.read(askBeforeDownloadProvider);
    if (!askBefore) {
      unawaited(ref.read(downloadQueueProvider.notifier).enqueue(track));
      return;
    }
    final sources = ref
            .read(extensionsProvider)
            .value
            ?.where((e) => e.enabled && e.hasDownloadProvider)
            .toList() ??
        [];
    if (!context.mounted) return;
    final choice = await showDownloadSheet(context, track: track, sources: sources);
    if (!context.mounted || choice == null) return;
    unawaited(ref
        .read(downloadQueueProvider.notifier)
        .enqueue(track, service: choice.sourceId, quality: choice.quality));
  }

  Future<void> _downloadAll(
    BuildContext context,
    WidgetRef ref,
    List<Track> tracks,
  ) async {
    if (tracks.isEmpty) return;
    final sources = ref
            .read(extensionsProvider)
            .value
            ?.where((e) => e.enabled && e.hasDownloadProvider)
            .toList() ??
        [];
    if (!context.mounted) return;
    final choice = await showDownloadSheet(
      context,
      track: tracks.first,
      sources: sources,
    );
    if (!context.mounted || choice == null) return;
    final queue = ref.read(downloadQueueProvider.notifier);
    for (final t in tracks) {
      unawaited(
        queue.enqueue(t, service: choice.sourceId, quality: choice.quality),
      );
    }
    if (context.mounted) {
      final t = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.batchAddedToQueue(tracks.length))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final async = ref.watch(_albumDataProvider(args));
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;

    return Scaffold(
      appBar: AppBar(title: Text(args.name)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) {
          return Column(
            children: [
              // Album header: cover + name + artist
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: data.coverUrl != null
                            ? Image.network(data.coverUrl!, fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  color: tokens.surface3,
                                  child: Icon(Icons.album, color: cs.onSurfaceVariant),
                                ))
                            : Container(
                                color: tokens.surface3,
                                child: Icon(Icons.album, color: cs.onSurfaceVariant),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: cs.onSurface),
                          ),
                          Text(
                            data.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (data.tracks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _downloadAll(context, ref, data.tracks),
                      icon: const Icon(Icons.download_outlined),
                      label: Text(t.downloadAll),
                    ),
                  ),
                ),
              const Divider(height: 1),
              if (data.tracks.isEmpty)
                Expanded(child: Center(child: Text(t.noTracksFound)))
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: data.tracks.length,
                    itemBuilder: (ctx, i) => TrackTile(
                      track: data.tracks[i],
                      qualityHint: data.tracks[i].qualityBadge,
                      onDownload: () => _onDownload(context, ref, data.tracks[i]),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

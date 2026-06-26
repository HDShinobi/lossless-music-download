import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../models/track.dart';
import '../providers/download_options_provider.dart';
import '../providers/download_queue_provider.dart';
import '../providers/extensions_provider.dart';
import '../providers/library_provider.dart';
import '../theme/app_tokens.dart';
import '../widgets/download_sheet.dart';
import 'album_screen.dart';

// ---------------------------------------------------------------------------
// Route args
// ---------------------------------------------------------------------------
class ArtistRouteArgs {
  const ArtistRouteArgs({required this.id, required this.name, this.coverUrl});
  final String id;
  final String name;
  final String? coverUrl;
}

// ---------------------------------------------------------------------------
// Local models
// ---------------------------------------------------------------------------
class ArtistAlbumCard {
  const ArtistAlbumCard({
    required this.id,
    required this.name,
    required this.artists,
    this.coverUrl,
    this.releaseDate,
    this.totalTracks = 0,
    this.albumType = 'album',
    this.providerId,
  });
  final String id;
  final String name;
  final String artists;
  final String? coverUrl;
  final String? releaseDate;
  final int totalTracks;
  final String albumType;
  final String? providerId;

  String get year {
    if (releaseDate != null && releaseDate!.length >= 4) {
      return releaseDate!.substring(0, 4);
    }
    return releaseDate ?? '';
  }
}

class ArtistData {
  const ArtistData({
    required this.name,
    this.imageUrl,
    this.listeners,
    required this.topTracks,
    required this.albums,
    required this.releases,
    required this.compilations,
  });
  final String name;
  final String? imageUrl;
  final int? listeners;
  final List<Track> topTracks;
  final List<ArtistAlbumCard> albums;
  final List<ArtistAlbumCard> releases;
  final List<ArtistAlbumCard> compilations;

  List<ArtistAlbumCard> get albumsOnly =>
      albums.where((a) => a.albumType == 'album').toList();
  List<ArtistAlbumCard> get singles =>
      albums.where((a) => a.albumType == 'single' || a.albumType == 'ep').toList();
}

// ---------------------------------------------------------------------------
// In-memory cache (10 minute TTL)
// ---------------------------------------------------------------------------
class _CacheEntry {
  _CacheEntry(this.data) : at = DateTime.now();
  final ArtistData data;
  final DateTime at;
  bool get valid =>
      DateTime.now().difference(at) < const Duration(minutes: 10);
}

final _cache = <String, _CacheEntry>{};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
List<ArtistAlbumCard> _parseAlbums(List<dynamic> raw) => raw
    .whereType<Map<String, dynamic>>()
    .map((a) => ArtistAlbumCard(
          id: a['id']?.toString() ?? '',
          name: (a['name'] ?? a['title'] ?? '').toString(),
          artists: (a['artists'] ?? a['artist'] ?? '').toString(),
          coverUrl: a['cover_url']?.toString() ?? a['images']?.toString(),
          releaseDate: a['release_date']?.toString(),
          totalTracks: a['total_tracks'] as int? ?? 0,
          albumType:
              (a['album_type'] ?? a['type'] ?? 'album').toString().toLowerCase(),
          providerId: a['provider_id']?.toString(),
        ))
    .where((a) => a.id.isNotEmpty && a.name.isNotEmpty)
    .toList();

List<Track> _parseTracks(List<dynamic> raw) =>
    raw.whereType<Map<String, dynamic>>().map(Track.fromJson).toList();

ArtistData _buildArtistData({
  required String fallbackName,
  required Map<String, dynamic> info,
  required List<dynamic> topTracks,
  required List<dynamic> albums,
  required List<dynamic> releases,
}) {
  final all = _parseAlbums(albums);
  return ArtistData(
    name: info['name']?.toString() ??
        info['display_name']?.toString() ??
        fallbackName,
    imageUrl: info['images']?.toString() ??
        info['header_image']?.toString() ??
        info['image_url']?.toString() ??
        info['cover_url']?.toString(),
    listeners: info['listeners'] as int?,
    topTracks: _parseTracks(topTracks),
    albums: all,
    releases: _parseAlbums(releases),
    compilations: all
        .where((a) => a.albumType == 'compilation')
        .toList(),
  );
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------
final _artistDataProvider =
    FutureProvider.family<ArtistData, String>((ref, artistId) async {
  if (_cache[artistId]?.valid == true) return _cache[artistId]!.data;

  final bridge = ref.read(backendBridgeProvider);

  ArtistData data;

  final colonIdx = artistId.indexOf(':');
  if (colonIdx > 0) {
    final provider = artistId.substring(0, colonIdx);
    final rawId = artistId.substring(colonIdx + 1);
    final result =
        await bridge.getProviderMetadata(provider, 'artist', rawId);
    if (result == null) {
      return ArtistData(
          name: artistId, topTracks: [], albums: [], releases: [], compilations: []);
    }
    final info =
        result['artist_info'] as Map<String, dynamic>? ?? {};
    data = _buildArtistData(
      fallbackName: artistId,
      info: info,
      topTracks: result['top_tracks'] as List? ?? [],
      albums: result['albums'] as List? ?? [],
      releases: result['releases'] as List? ?? [],
    );
  } else {
    final result = await bridge.handleUrl(
        'https://open.spotify.com/artist/$artistId');
    if (result == null) {
      return ArtistData(
          name: artistId, topTracks: [], albums: [], releases: [], compilations: []);
    }
    final artistMap = result['artist'] as Map<String, dynamic>?;
    if (artistMap == null) {
      return ArtistData(
          name: artistId, topTracks: [], albums: [], releases: [], compilations: []);
    }
    data = _buildArtistData(
      fallbackName: artistId,
      info: artistMap,
      topTracks: artistMap['top_tracks'] as List? ?? [],
      albums: artistMap['albums'] as List? ?? [],
      releases: artistMap['releases'] as List? ?? [],
    );
  }

  _cache[artistId] = _CacheEntry(data);
  return data;
});

// ---------------------------------------------------------------------------
// ArtistScreen
// ---------------------------------------------------------------------------
class ArtistScreen extends ConsumerStatefulWidget {
  const ArtistScreen({
    super.key,
    required this.id,
    required this.name,
    this.coverUrl,
  });

  final String id;
  final String name;
  final String? coverUrl;

  @override
  ConsumerState<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends ConsumerState<ArtistScreen> {
  final _scroll = ScrollController();
  final _popularPageCtrl = PageController();
  bool _titleVisible = false;
  int _popularPage = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final show = _scroll.offset > 300;
      if (show != _titleVisible) setState(() => _titleVisible = show);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _popularPageCtrl.dispose();
    super.dispose();
  }

  // ---- Download helpers ----

  Future<void> _showPickerSheet(BuildContext context, Track track) async {
    final t = AppLocalizations.of(context);
    final queue = ref.read(downloadQueueProvider.notifier);
    final sources = ref
            .read(extensionsProvider)
            .value
            ?.where((e) => e.enabled && e.hasDownloadProvider)
            .toList() ??
        [];
    if (!context.mounted) return;
    final choice =
        await showDownloadSheet(context, track: track, sources: sources);
    if (!context.mounted || choice == null) return;
    unawaited(queue
        .enqueue(track, service: choice.sourceId, quality: choice.quality)
        .catchError((_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t.downloadFailed)));
      }
    }));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t.downloadStarted)));
  }

  Future<void> _quickDownload(BuildContext context, Track track) async {
    final t = AppLocalizations.of(context);
    final queue = ref.read(downloadQueueProvider.notifier);
    final askBefore = ref.read(askBeforeDownloadProvider);
    if (!askBefore) {
      unawaited(queue.enqueue(track).catchError((_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(t.downloadFailed)));
        }
      }));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.downloadStarted)));
      return;
    }
    await _showPickerSheet(context, track);
  }

  Future<void> _downloadTracks(
      BuildContext context, List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final t = AppLocalizations.of(context);
    final queue = ref.read(downloadQueueProvider.notifier);
    final sources = ref
            .read(extensionsProvider)
            .value
            ?.where((e) => e.enabled && e.hasDownloadProvider)
            .toList() ??
        [];
    if (!context.mounted) return;
    final choice =
        await showDownloadSheet(context, track: tracks.first, sources: sources);
    if (!context.mounted || choice == null) return;
    for (final track in tracks) {
      unawaited(queue.enqueue(track,
          service: choice.sourceId, quality: choice.quality));
    }
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.batchAddedToQueue(tracks.length))));
  }

  void _showDownloadAllOptions(BuildContext context, ArtistData data) {
    final t = AppLocalizations.of(context);
    final allTracks = data.topTracks;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            _DownloadOption(
              icon: Icons.download_outlined,
              label: t.downloadOptionsAll,
              subtitle: '${allTracks.length} tracks',
              onTap: () {
                Navigator.pop(ctx);
                _downloadTracks(context, allTracks);
              },
            ),
            _DownloadOption(
              icon: Icons.album_outlined,
              label: t.downloadOptionsAlbumsOnly,
              subtitle: '${data.albumsOnly.length} albums',
              onTap: () {
                Navigator.pop(ctx);
                final tracks = data.albumsOnly
                    .expand((a) => <Track>[])
                    .toList();
                _downloadTracks(context, tracks);
              },
            ),
            _DownloadOption(
              icon: Icons.music_note_outlined,
              label: t.downloadOptionsSinglesOnly,
              subtitle: '${data.singles.length} singles',
              onTap: () {
                Navigator.pop(ctx);
                final tracks =
                    data.singles.expand((a) => <Track>[]).toList();
                _downloadTracks(context, tracks);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _openAlbum(BuildContext context, ArtistAlbumCard album) {
    context.push(
      '/search/album',
      extra: AlbumRouteArgs(
        id: album.id,
        name: album.name,
        artist: album.artists,
        coverUrl: album.coverUrl,
      ),
    );
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(_artistDataProvider(widget.id));
    final library = ref.watch(libraryProvider).value ?? [];

    // Build a quick lookup set: normalized track names in library
    final libraryNames = library
        .map((e) {
          final n = e.name.toLowerCase();
          // strip leading "01. " pattern and extension
          return n.replaceAll(RegExp(r'^\d+\.\s*'), '').replaceAll(RegExp(r'\.\w+$'), '');
        })
        .toSet();

    return Scaffold(
      body: async.when(
        loading: () => CustomScrollView(
          slivers: [
            _buildAppBar(context, cs, data: null),
            const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator())),
          ],
        ),
        error: (e, _) => CustomScrollView(
          slivers: [
            _buildAppBar(context, cs, data: null),
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('$e',
                      style: TextStyle(color: cs.error),
                      textAlign: TextAlign.center),
                ),
              ),
            ),
          ],
        ),
        data: (data) => CustomScrollView(
          controller: _scroll,
          slivers: [
            _buildAppBar(context, cs, data: data),

            // Popular tracks
            if (data.topTracks.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _SectionHeader(
                  title: t.artistSectionCount(t.artistPopular, data.topTracks.length.clamp(0, 10)),
                ),
              ),
              SliverToBoxAdapter(
                child: _PopularCarousel(
                  tracks: data.topTracks.take(10).toList(),
                  libraryNames: libraryNames,
                  pageCtrl: _popularPageCtrl,
                  currentPage: _popularPage,
                  onPageChanged: (p) => setState(() => _popularPage = p),
                  onRowTap: (track) => _showPickerSheet(context, track),
                  onDownload: (track) => _quickDownload(context, track),
                  onAlbumTap: (track) {
                    if (track.albumId != null && track.albumName != null) {
                      _openAlbum(
                        context,
                        ArtistAlbumCard(
                          id: track.albumId!,
                          name: track.albumName!,
                          artists: track.artists,
                          coverUrl: track.coverUrl,
                        ),
                      );
                    }
                  },
                ),
              ),
            ],

            // Releases (new releases from provider)
            if (data.releases.isNotEmpty)
              _buildAlbumSection(
                  context, t.artistSectionCount(t.artistReleases, data.releases.length), data.releases),

            // Albums
            if (data.albumsOnly.isNotEmpty)
              _buildAlbumSection(
                  context, t.artistSectionCount(t.artistAlbums, data.albumsOnly.length), data.albumsOnly),

            // Singles & EPs
            if (data.singles.isNotEmpty)
              _buildAlbumSection(
                  context, t.artistSectionCount(t.artistSingles, data.singles.length), data.singles),

            // Compilations
            if (data.compilations.isNotEmpty)
              _buildAlbumSection(
                  context, t.artistSectionCount(t.artistCompilations, data.compilations.length), data.compilations),

            const SliverToBoxAdapter(child: SizedBox(height: 48)),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumSection(
    BuildContext context,
    String title,
    List<ArtistAlbumCard> albums,
  ) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: title),
          _AlbumScroll(albums: albums, onTap: (a) => _openAlbum(context, a)),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(
    BuildContext context,
    ColorScheme cs, {
    required ArtistData? data,
  }) {
    final t = AppLocalizations.of(context);
    final imageUrl = data?.imageUrl ?? widget.coverUrl;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String? listenersText;
    if (data?.listeners != null && data!.listeners! > 0) {
      final n = data.listeners!;
      final compact = n >= 1_000_000
          ? '${(n / 1_000_000).toStringAsFixed(1)}M'
          : n >= 1_000
              ? '${(n / 1_000).toStringAsFixed(0)}K'
              : '$n';
      listenersText = t.artistMonthlyListeners(compact);
    }

    return SliverAppBar(
      expandedHeight: 380,
      pinned: true,
      stretch: true,
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: _CircleButton(
          icon: Icons.arrow_back,
          onTap: () => Navigator.of(context).pop(),
        ),
      ),
      title: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _titleVisible ? 1.0 : 0.0,
        child: Text(
          data?.name ?? widget.name,
          style: TextStyle(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.none,
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Background image
            if (hasImage)
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (context, e, st) => Container(
                  color: cs.surfaceContainerHighest,
                  child: Icon(Icons.person, size: 80, color: cs.onSurfaceVariant),
                ),
              )
            else
              Container(
                color: cs.surfaceContainerHighest,
                child: Icon(Icons.person, size: 80, color: cs.onSurfaceVariant),
              ),

            // Gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.2),
                    Colors.black.withValues(alpha: 0.65),
                    isDark ? cs.surface : Colors.black.withValues(alpha: 0.85),
                  ],
                  stops: const [0.0, 0.4, 0.72, 1.0],
                ),
              ),
            ),

            // Bottom info row
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          data?.name ?? widget.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                  offset: Offset(0, 1),
                                  blurRadius: 4,
                                  color: Color(0x88000000))
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (listenersText != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            listenersText,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (data != null) ...[
                    const SizedBox(width: 8),
                    _CircleButton(
                      icon: Icons.download_outlined,
                      onTap: () => _showDownloadAllOptions(context, data),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Popular tracks — PageView carousel
// ---------------------------------------------------------------------------
class _PopularCarousel extends StatelessWidget {
  const _PopularCarousel({
    required this.tracks,
    required this.libraryNames,
    required this.pageCtrl,
    required this.currentPage,
    required this.onPageChanged,
    required this.onRowTap,
    required this.onDownload,
    required this.onAlbumTap,
  });

  final List<Track> tracks;
  final Set<String> libraryNames;
  final PageController pageCtrl;
  final int currentPage;
  final void Function(int) onPageChanged;
  final void Function(Track) onRowTap;
  final void Function(Track) onDownload;
  final void Function(Track) onAlbumTap;

  static const _perPage = 5;

  bool _inLibrary(Track t) {
    final normalized =
        t.name.toLowerCase().replaceAll(RegExp(r'^\d+\.\s*'), '');
    return libraryNames.contains(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = (tracks.length / _perPage).ceil();
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        SizedBox(
          height: _perPage * 64.0,
          child: PageView.builder(
            controller: pageCtrl,
            itemCount: pageCount,
            onPageChanged: onPageChanged,
            itemBuilder: (ctx, pageIdx) {
              final start = pageIdx * _perPage;
              final end = (start + _perPage).clamp(0, tracks.length);
              final pageTracks = tracks.sublist(start, end);
              return Column(
                children: List.generate(pageTracks.length, (i) {
                  final track = pageTracks[i];
                  final rank = start + i + 1;
                  return _PopularTrackRow(
                    track: track,
                    rank: rank,
                    inLibrary: _inLibrary(track),
                    onTap: () => onRowTap(track),
                    onDownload: () => onDownload(track),
                    onAlbumTap: () => onAlbumTap(track),
                  );
                }),
              );
            },
          ),
        ),
        if (pageCount > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                pageCount,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == currentPage ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == currentPage
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PopularTrackRow extends StatelessWidget {
  const _PopularTrackRow({
    required this.track,
    required this.rank,
    required this.inLibrary,
    required this.onTap,
    required this.onDownload,
    required this.onAlbumTap,
  });

  final Track track;
  final int rank;
  final bool inLibrary;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  final VoidCallback onAlbumTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            // Rank
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Cover
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox.square(
                dimension: 48,
                child: track.coverUrl != null
                    ? Image.network(track.coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, e, st) => Container(
                            color: tokens.surface3,
                            child: Icon(Icons.music_note,
                                size: 24, color: cs.onSurfaceVariant)))
                    : Container(
                        color: tokens.surface3,
                        child: Icon(Icons.music_note,
                            size: 24, color: cs.onSurfaceVariant)),
              ),
            ),
            const SizedBox(width: 12),
            // Track info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface,
                        fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: GestureDetector(
                          onTap: track.albumName != null ? onAlbumTap : null,
                          child: Text(
                            track.albumName ?? track.artists,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                              decoration: track.albumName != null
                                  ? TextDecoration.underline
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      if (inLibrary) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            t.inLibrary,
                            style: TextStyle(
                                fontSize: 10,
                                color: cs.primary,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Download button
            IconButton(
              onPressed: onDownload,
              icon: Icon(Icons.download_outlined,
                  size: 20, color: cs.onSurfaceVariant),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Horizontal album scroll
// ---------------------------------------------------------------------------
class _AlbumScroll extends StatelessWidget {
  const _AlbumScroll({required this.albums, required this.onTap});
  final List<ArtistAlbumCard> albums;
  final void Function(ArtistAlbumCard) onTap;

  static const double _tileSize = 140;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;

    return SizedBox(
      height: _tileSize + 76,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: albums.length,
        itemBuilder: (ctx, i) {
          final album = albums[i];
          return GestureDetector(
            onTap: () => onTap(album),
            child: Container(
              width: _tileSize,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox.square(
                          dimension: _tileSize,
                          child: album.coverUrl != null
                              ? Image.network(
                                  album.coverUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, e, st) =>
                                      _AlbumPlaceholder(
                                          cs: cs, tokens: tokens),
                                )
                              : _AlbumPlaceholder(cs: cs, tokens: tokens),
                        ),
                      ),
                      // Type badge for singles/eps
                      if (album.albumType == 'single' ||
                          album.albumType == 'ep')
                        Positioned(
                          bottom: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              album.albumType.toUpperCase(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    album.name,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    album.totalTracks > 0
                        ? '${album.year}  ·  ${album.totalTracks} tracks'
                        : album.year,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AlbumPlaceholder extends StatelessWidget {
  const _AlbumPlaceholder({required this.cs, required this.tokens});
  final ColorScheme cs;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) => Container(
        color: tokens.surface3,
        child: Icon(Icons.album, color: cs.onSurfaceVariant, size: 40),
      );
}

// ---------------------------------------------------------------------------
// Small circle button (for header actions)
// ---------------------------------------------------------------------------
class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Download option row in modal
// ---------------------------------------------------------------------------
class _DownloadOption extends StatelessWidget {
  const _DownloadOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: cs.primary),
      title: Text(label),
      subtitle: Text(subtitle,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      onTap: onTap,
    );
  }
}

import 'package:go_router/go_router.dart';
import 'package:flutter/widgets.dart';
import 'providers/library_provider.dart';
import 'widgets/main_shell.dart';
import 'screens/search_screen.dart';
import 'screens/artist_screen.dart';
import 'screens/album_screen.dart';
import 'screens/queue_screen.dart';
import 'screens/server_screen.dart';
import 'screens/library_album_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sources_screen.dart';
import 'screens/extension_detail_screen.dart';
import 'screens/verified_screen.dart';

GoRoute _r(String path, Widget child) =>
    GoRoute(path: path, builder: (c, s) => child);

final appRouter = GoRouter(
  initialLocation: '/search',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (c, s, shell) => MainShell(shell: shell),
      branches: [
        // 0 — Search
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/search',
            builder: (c, s) => const SearchScreen(),
            routes: [
              GoRoute(
                path: 'artist',
                builder: (c, s) {
                  final args = s.extra as ArtistRouteArgs;
                  return ArtistScreen(
                    id: args.id,
                    name: args.name,
                    coverUrl: args.coverUrl,
                  );
                },
              ),
              GoRoute(
                path: 'album',
                builder: (c, s) {
                  final args = s.extra as AlbumRouteArgs;
                  return AlbumScreen(args: args);
                },
              ),
            ],
          ),
        ]),
        // 1 — Library
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/library',
            builder: (c, s) => const LibraryScreen(),
            routes: [
              GoRoute(
                path: 'verified',
                builder: (c, s) =>
                    VerifiedScreen(entry: s.extra as LibraryEntry),
              ),
              GoRoute(
                path: 'album',
                builder: (c, s) {
                  final args = s.extra as LibraryAlbumRouteArgs;
                  return LibraryAlbumScreen(
                    artistName: args.artistName,
                    albumName: args.albumName,
                  );
                },
              ),
            ],
          ),
        ]),
        // 2 — Queue
        StatefulShellBranch(routes: [_r('/queue', const QueueScreen())]),
        // 3 — Server
        StatefulShellBranch(routes: [_r('/server', const ServerScreen())]),
        // 4 — Settings
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/settings',
            builder: (c, s) => const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'sources',
                builder: (c, s) => const SourcesScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (c, s) =>
                        ExtensionDetailScreen(id: s.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
        ]),
      ],
    ),
  ],
);

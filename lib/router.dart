import 'package:go_router/go_router.dart';
import 'package:flutter/widgets.dart';
import 'widgets/main_shell.dart';
import 'screens/search_screen.dart';
import 'screens/queue_screen.dart';
import 'screens/server_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sources_screen.dart';
import 'screens/extension_detail_screen.dart';

GoRoute _r(String path, Widget child) =>
    GoRoute(path: path, builder: (c, s) => child);

final appRouter = GoRouter(
  initialLocation: '/search',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (c, s, shell) => MainShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [_r('/search', const SearchScreen())]),
        StatefulShellBranch(routes: [_r('/queue', const QueueScreen())]),
        StatefulShellBranch(routes: [_r('/server', const ServerScreen())]),
        StatefulShellBranch(routes: [_r('/library', const LibraryScreen())]),
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

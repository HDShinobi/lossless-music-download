import 'package:go_router/go_router.dart';
import 'package:flutter/widgets.dart';
import 'widgets/main_shell.dart';
import 'screens/search_screen.dart';
import 'screens/queue_screen.dart';
import 'screens/server_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';

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
        StatefulShellBranch(routes: [_r('/settings', const SettingsScreen())]),
      ],
    ),
  ],
);

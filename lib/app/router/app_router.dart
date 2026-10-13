import 'package:go_router/go_router.dart';

import '../presentation/widgets/app_shell.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/items/presentation/pages/items_page.dart';
import '../../features/outings/presentation/pages/outings_page.dart';

GoRouter createAppRouter({String initialLocation = '/home'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/home'),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/items',
                builder: (context, state) => const ItemsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/outings',
                builder: (context, state) => const OutingsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

final GoRouter appRouter = createAppRouter();

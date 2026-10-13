import 'package:go_router/go_router.dart';

import '../presentation/widgets/app_shell.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/items/presentation/pages/item_detail_page.dart';
import '../../features/items/presentation/pages/item_edit_page.dart';
import '../../features/items/presentation/pages/item_search_page.dart';
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
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (context, state) {
                      final locStr = state.uri.queryParameters['locationId'];
                      final locId = locStr == null
                          ? null
                          : int.tryParse(locStr);
                      return ItemEditPage(initialLocationId: locId);
                    },
                  ),
                  GoRoute(
                    path: 'search',
                    builder: (context, state) => const ItemSearchPage(),
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (context, state) {
                      final id = int.parse(state.pathParameters['id']!);
                      return ItemDetailPage(itemId: id);
                    },
                    routes: [
                      GoRoute(
                        path: 'edit',
                        builder: (context, state) {
                          final id = int.parse(state.pathParameters['id']!);
                          return ItemEditPage(itemId: id);
                        },
                      ),
                    ],
                  ),
                ],
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

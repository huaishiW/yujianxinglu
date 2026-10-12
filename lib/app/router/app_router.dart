import 'package:go_router/go_router.dart';

import '../../features/home/home_page.dart';
import '../../features/items/items_page.dart';
import '../../features/locations/locations_page.dart';
import '../../features/outing_sessions/outing_sessions_page.dart';
import '../../features/outing_templates/outing_templates_page.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => const HomePage(),
    ),
    GoRoute(
      path: '/locations',
      name: 'locations',
      builder: (context, state) => const LocationsPage(),
    ),
    GoRoute(
      path: '/items',
      name: 'items',
      builder: (context, state) => const ItemsPage(),
    ),
    GoRoute(
      path: '/outing-templates',
      name: 'outing-templates',
      builder: (context, state) => const OutingTemplatesPage(),
    ),
    GoRoute(
      path: '/outing-sessions',
      name: 'outing-sessions',
      builder: (context, state) => const OutingSessionsPage(),
    ),
  ],
);

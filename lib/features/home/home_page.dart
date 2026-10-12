import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final destinations = [
      (label: 'Locations', route: '/locations', icon: Icons.place_outlined),
      (label: 'Items', route: '/items', icon: Icons.inventory_2_outlined),
      (
        label: 'Outing templates',
        route: '/outing-templates',
        icon: Icons.view_list_outlined,
      ),
      (
        label: 'Outing sessions',
        route: '/outing-sessions',
        icon: Icons.directions_walk_outlined,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Personal Items Assistant')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Organize the things you need before going out.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          for (final destination in destinations)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton.tonalIcon(
                onPressed: () => context.go(destination.route),
                icon: Icon(destination.icon),
                label: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(destination.label),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

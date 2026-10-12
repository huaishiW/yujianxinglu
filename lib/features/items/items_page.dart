import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_page.dart';

class ItemsPage extends StatelessWidget {
  const ItemsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderPage(
      title: 'Items',
      description: 'Manage personal items and their storage locations.',
      icon: Icons.inventory_2_outlined,
    );
  }
}

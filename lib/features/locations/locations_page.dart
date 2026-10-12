import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_page.dart';

class LocationsPage extends StatelessWidget {
  const LocationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderPage(
      title: 'Locations',
      description: 'Manage the places where your items are stored.',
      icon: Icons.place_outlined,
    );
  }
}

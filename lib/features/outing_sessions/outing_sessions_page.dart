import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_page.dart';

class OutingSessionsPage extends StatelessWidget {
  const OutingSessionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderPage(
      title: 'Outing sessions',
      description: 'Track the items needed for an outing in progress.',
      icon: Icons.directions_walk_outlined,
    );
  }
}

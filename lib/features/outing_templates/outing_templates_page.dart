import 'package:flutter/material.dart';

import '../../shared/widgets/feature_placeholder_page.dart';

class OutingTemplatesPage extends StatelessWidget {
  const OutingTemplatesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderPage(
      title: 'Outing templates',
      description: 'Create reusable packing lists for common outings.',
      icon: Icons.view_list_outlined,
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../data/local/app_database.dart';

class LocationBreadcrumbs extends StatelessWidget {
  const LocationBreadcrumbs({
    required this.breadcrumbs,
    required this.onRootTap,
    required this.onBreadcrumbTap,
    required this.onUpTap,
    super.key,
  });

  final List<Location> breadcrumbs;
  final VoidCallback onRootTap;
  final ValueChanged<int> onBreadcrumbTap;
  final VoidCallback? onUpTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          if (onUpTap != null)
            IconButton(
              onPressed: onUpTap,
              tooltip: '返回上一级',
              icon: const Icon(Icons.arrow_back),
            ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  TextButton(
                    onPressed: breadcrumbs.isEmpty ? null : onRootTap,
                    child: const Text('我的收纳位置'),
                  ),
                  for (var index = 0; index < breadcrumbs.length; index += 1)
                    _BreadcrumbSegment(
                      name: breadcrumbs[index].name,
                      isLast: index == breadcrumbs.length - 1,
                      onTap: () => onBreadcrumbTap(index),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BreadcrumbSegment extends StatelessWidget {
  const _BreadcrumbSegment({
    required this.name,
    required this.isLast,
    required this.onTap,
  });

  final String name;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('/'),
        TextButton(
          onPressed: isLast ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }
}

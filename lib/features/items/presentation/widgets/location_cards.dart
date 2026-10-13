import 'package:flutter/material.dart';

import '../../../../data/local/app_database.dart';

enum LocationAction { rename, move, delete }

class LocationActionsButton extends StatelessWidget {
  const LocationActionsButton({
    required this.onSelected,
    this.iconColor,
    super.key,
  });

  final ValueChanged<LocationAction> onSelected;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<LocationAction>(
      tooltip: '更多操作',
      icon: Icon(Icons.more_vert, color: iconColor),
      onSelected: onSelected,
      itemBuilder: (context) => const [
        PopupMenuItem(value: LocationAction.rename, child: Text('重命名')),
        PopupMenuItem(value: LocationAction.move, child: Text('移动')),
        PopupMenuItem(value: LocationAction.delete, child: Text('删除')),
      ],
    );
  }
}

class LocationCard extends StatelessWidget {
  const LocationCard({
    required this.location,
    required this.onOpen,
    required this.onAction,
    super.key,
  });

  final Location location;
  final VoidCallback onOpen;
  final ValueChanged<LocationAction> onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey('location-card-${location.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onOpen,
        leading: const CircleAvatar(child: Icon(Icons.folder_outlined)),
        title: Text(
          location.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: const Text('进入下一级'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LocationActionsButton(onSelected: onAction),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class DirectItemCard extends StatelessWidget {
  const DirectItemCard({required this.item, this.onTap, super.key});

  final Item item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey('direct-item-card-${item.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
        title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text('数量：${item.quantity}'),
        trailing: onTap != null ? const Icon(Icons.chevron_right) : null,
      ),
    );
  }
}

class LocationSectionHeader extends StatelessWidget {
  const LocationSectionHeader({required this.title, this.action, super.key});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          action ?? const SizedBox.shrink(),
        ],
      ),
    );
  }
}

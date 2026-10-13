import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/local/app_database.dart';
import '../../application/location_providers.dart';

class LocationMoveTarget {
  const LocationMoveTarget({required this.parentId});

  final int? parentId;
}

class LocationTargetPicker extends ConsumerStatefulWidget {
  const LocationTargetPicker({required this.sourceId, super.key});

  final int sourceId;

  @override
  ConsumerState<LocationTargetPicker> createState() =>
      _LocationTargetPickerState();
}

class _LocationTargetPickerState extends ConsumerState<LocationTargetPicker> {
  int? _currentLocationId;
  final List<Location> _breadcrumbs = [];

  @override
  Widget build(BuildContext context) {
    final children = ref.watch(locationChildrenProvider(_currentLocationId));
    final currentPath = _currentLocationId == null
        ? '我的收纳位置'
        : _breadcrumbs.map((location) => location.name).join(' / ');

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _breadcrumbs.isEmpty
                        ? () => Navigator.of(context).pop()
                        : _goUp,
                    tooltip: _breadcrumbs.isEmpty ? '关闭' : '返回上一级',
                    icon: Icon(
                      _breadcrumbs.isEmpty ? Icons.close : Icons.arrow_back,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '选择移动目标',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: const Text('当前目标父位置'),
                  subtitle: Text(
                    currentPath,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: FilledButton(
                    onPressed: _selectCurrentLocation,
                    child: const Text('选择此处'),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: children.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => _PickerError(
                  onRetry: () {
                    ref.invalidate(
                      locationChildrenProvider(_currentLocationId),
                    );
                  },
                ),
                data: (locations) {
                  if (locations.isEmpty) {
                    return const Center(child: Text('当前没有下级位置'));
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: locations.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final location = locations[index];
                      final isSource = location.id == widget.sourceId;
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          enabled: !isSource,
                          leading: Icon(
                            isSource
                                ? Icons.block_outlined
                                : Icons.folder_outlined,
                          ),
                          title: Text(
                            location.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: isSource
                              ? const Text('不能移动到自身或其后代')
                              : const Text('进入此位置'),
                          trailing: Icon(
                            isSource ? Icons.lock_outline : Icons.chevron_right,
                          ),
                          onTap: isSource
                              ? null
                              : () => _openLocation(location),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openLocation(Location location) {
    setState(() {
      _currentLocationId = location.id;
      _breadcrumbs.add(location);
    });
  }

  void _goUp() {
    if (_breadcrumbs.isEmpty) {
      return;
    }
    setState(() {
      _breadcrumbs.removeLast();
      _currentLocationId = _breadcrumbs.isEmpty ? null : _breadcrumbs.last.id;
    });
  }

  void _selectCurrentLocation() {
    Navigator.of(context).pop(LocationMoveTarget(parentId: _currentLocationId));
  }
}

class _PickerError extends StatelessWidget {
  const _PickerError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('读取目标位置失败'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重新加载'),
          ),
        ],
      ),
    );
  }
}

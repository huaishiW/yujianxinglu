import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../data/local/app_database.dart';
import '../../application/location_providers.dart';

class ItemLocationPicker extends ConsumerStatefulWidget {
  const ItemLocationPicker({this.initialLocationId, super.key});

  final int? initialLocationId;

  static Future<Location?> show(
    BuildContext context, {
    int? initialLocationId,
  }) {
    return showModalBottomSheet<Location>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          ItemLocationPicker(initialLocationId: initialLocationId),
    );
  }

  @override
  ConsumerState<ItemLocationPicker> createState() => _ItemLocationPickerState();
}

class _ItemLocationPickerState extends ConsumerState<ItemLocationPicker> {
  int? _currentLocationId;
  final List<Location> _breadcrumbs = [];
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initPath();
  }

  Future<void> _initPath() async {
    final initialId = widget.initialLocationId;
    if (initialId != null) {
      try {
        final locationRepo = ref.read(locationRepositoryProvider);
        final path = <Location>[];
        final visited = <int>{};
        Location? current = await locationRepo.getById(initialId);
        while (current != null) {
          if (!visited.add(current.id)) break;
          path.insert(0, current);
          current = current.parentId == null
              ? null
              : await locationRepo.getById(current.parentId!);
        }
        if (mounted) {
          setState(() {
            _breadcrumbs.addAll(path);
            _currentLocationId = initialId;
            _initialized = true;
          });
        }
        return;
      } catch (_) {
        // Fallback to root
      }
    }
    if (mounted) {
      setState(() {
        _initialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final children = ref.watch(locationChildrenProvider(_currentLocationId));
    final currentPath = _currentLocationId == null
        ? '我的收纳位置'
        : _breadcrumbs.map((l) => l.name).join(' / ');
    final canSelectCurrent =
        _currentLocationId != null && _breadcrumbs.isNotEmpty;

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
                      '选择存放位置',
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
                  title: const Text('当前选定位置'),
                  subtitle: Text(
                    currentPath,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: FilledButton(
                    onPressed: canSelectCurrent ? _selectCurrentLocation : null,
                    child: const Text('选定此处'),
                  ),
                ),
              ),
            ),
            if (!canSelectCurrent)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '物品必须存放在具体收纳位置中，请进入下方位置',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: children.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('读取收纳位置失败'),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          ref.invalidate(
                            locationChildrenProvider(_currentLocationId),
                          );
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('重新加载'),
                      ),
                    ],
                  ),
                ),
                data: (locations) {
                  if (locations.isEmpty) {
                    return const Center(child: Text('当前层级下没有更多子位置'));
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: locations.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final location = locations[index];
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(
                            location.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: const Text('进入下一级'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => _selectLocation(location),
                                child: const Text('直接选择'),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          onTap: () => _openLocation(location),
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
    if (_breadcrumbs.isNotEmpty) {
      Navigator.of(context).pop(_breadcrumbs.last);
    }
  }

  void _selectLocation(Location location) {
    Navigator.of(context).pop(location);
  }
}

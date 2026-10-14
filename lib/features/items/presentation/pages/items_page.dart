import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../data/local/app_database.dart';
import '../../../../data/repositories/location_repository.dart';
import '../../application/location_providers.dart';
import '../widgets/location_breadcrumbs.dart';
import '../widgets/location_cards.dart';
import '../widgets/location_name_dialog.dart';
import '../widgets/location_target_picker.dart';

class ItemsPage extends ConsumerStatefulWidget {
  const ItemsPage({super.key});

  @override
  ConsumerState<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends ConsumerState<ItemsPage> {
  int? _currentLocationId;
  final List<Location> _breadcrumbs = [];
  bool _isActionInProgress = false;

  @override
  Widget build(BuildContext context) {
    final currentLocationId = _currentLocationId;
    final locations = ref.watch(locationChildrenProvider(currentLocationId));
    final directItems = currentLocationId == null
        ? null
        : ref.watch(locationDirectItemsProvider(currentLocationId));

    return PopScope(
      canPop: currentLocationId == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && currentLocationId != null) {
          _goUp();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('物品'),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: '搜索物品',
              onPressed: () => context.push('/items/search'),
            ),
            IconButton(
              icon: const Icon(Icons.add_box_outlined),
              tooltip: '添加物品',
              onPressed: () => context.push(
                currentLocationId == null
                    ? '/items/new'
                    : '/items/new?locationId=$currentLocationId',
              ),
            ),
            if (currentLocationId != null)
              LocationActionsButton(
                onSelected: (action) {
                  unawaited(_handleLocationAction(_breadcrumbs.last, action));
                },
              ),
          ],
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refreshCurrentLevel,
            child: ListView(
              key: const ValueKey('location-browser'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 104),
              children: [
                Text(
                  currentLocationId == null ? '收纳位置' : _breadcrumbs.last.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                LocationBreadcrumbs(
                  breadcrumbs: List.unmodifiable(_breadcrumbs),
                  onRootTap: _goToRoot,
                  onBreadcrumbTap: _goToBreadcrumb,
                  onUpTap: currentLocationId == null ? null : _goUp,
                ),
                const SizedBox(height: 4),
                _buildLocationSection(locations),
                if (directItems != null) ...[
                  const SizedBox(height: 8),
                  _buildItemSection(directItems),
                ],
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _isActionInProgress ? null : _showCreateLocationDialog,
          icon: const Icon(Icons.add),
          label: Text(currentLocationId == null ? '新建位置' : '新建子位置'),
        ),
      ),
    );
  }

  Widget _buildLocationSection(AsyncValue<List<Location>> locations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LocationSectionHeader(title: '子位置'),
        locations.when(
          loading: () => const _SectionLoading(),
          error: (error, stackTrace) => _SectionError(
            message: _friendlyError(error, fallback: '读取子位置失败，请重试'),
            onRetry: () =>
                ref.invalidate(locationChildrenProvider(_currentLocationId)),
          ),
          data: (locationList) {
            if (locationList.isEmpty) {
              return _SectionEmpty(
                text: _currentLocationId == null ? '还没有收纳位置' : '当前没有子位置',
                icon: Icons.folder_open_outlined,
              );
            }
            return Column(
              children: [
                for (final location in locationList)
                  LocationCard(
                    location: location,
                    onOpen: () => _openLocation(location),
                    onAction: (action) {
                      unawaited(_handleLocationAction(location, action));
                    },
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildItemSection(AsyncValue<List<Item>> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LocationSectionHeader(
          title: '当前直接存放的物品',
          action: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('添加物品'),
            onPressed: () {
              if (_currentLocationId != null) {
                context.push('/items/new?locationId=$_currentLocationId');
              }
            },
          ),
        ),
        items.when(
          loading: () => const _SectionLoading(),
          error: (error, stackTrace) => _SectionError(
            message: _friendlyError(error, fallback: '读取直接物品失败，请重试'),
            onRetry: () => ref.invalidate(
              locationDirectItemsProvider(_currentLocationId!),
            ),
          ),
          data: (itemList) {
            if (itemList.isEmpty) {
              return const _SectionEmpty(
                text: '当前没有直接存放的物品',
                icon: Icons.inventory_2_outlined,
              );
            }
            return Column(
              children: [
                for (final item in itemList)
                  DirectItemCard(
                    item: item,
                    onTap: () => context.push('/items/${item.id}'),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _openLocation(Location location) {
    setState(() {
      _currentLocationId = location.id;
      _breadcrumbs.add(location);
    });
  }

  void _goToRoot() {
    if (_currentLocationId == null) {
      return;
    }
    setState(() {
      _currentLocationId = null;
      _breadcrumbs.clear();
    });
  }

  void _goToBreadcrumb(int index) {
    if (index < 0 || index >= _breadcrumbs.length - 1) {
      return;
    }
    setState(() {
      _currentLocationId = _breadcrumbs[index].id;
      _breadcrumbs.removeRange(index + 1, _breadcrumbs.length);
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

  Future<void> _showCreateLocationDialog() async {
    final parentId = _currentLocationId;
    final parentPath = parentId == null
        ? '我的收纳位置'
        : _breadcrumbs.map((location) => location.name).join(' / ');

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => LocationNameDialog(
        title: parentId == null ? '新建顶层位置' : '新建子位置',
        parentPath: parentPath,
        onSubmit: (name) async {
          await ref
              .read(locationRepositoryProvider)
              .create(name: name, parentId: parentId);
          ref.invalidate(locationChildrenProvider(parentId));
        },
      ),
    );
  }

  Future<void> _handleLocationAction(
    Location location,
    LocationAction action,
  ) async {
    if (_isActionInProgress) {
      return;
    }
    switch (action) {
      case LocationAction.rename:
        await _renameLocation(location);
      case LocationAction.move:
        await _moveLocation(location);
      case LocationAction.delete:
        await _deleteLocation(location);
    }
  }

  Future<void> _renameLocation(Location location) async {
    if (_isActionInProgress) {
      return;
    }
    setState(() => _isActionInProgress = true);

    try {
      final parentPath = location.parentId == null
          ? '我的收纳位置'
          : await _pathForLocation(location.parentId!);
      if (!mounted) {
        return;
      }

      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => LocationNameDialog(
          title: '重命名位置',
          initialName: location.name,
          parentPath: parentPath,
          onSubmit: (name) async {
            await ref
                .read(locationRepositoryProvider)
                .rename(location.id, name);
            ref.invalidate(locationChildrenProvider(location.parentId));
            if (location.id == _currentLocationId) {
              final path = await _loadPathToLocation(location.id);
              if (!mounted) {
                return;
              }
              setState(() {
                _breadcrumbs
                  ..clear()
                  ..addAll(path);
              });
            }
          },
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isActionInProgress = false);
      }
    }
  }

  Future<void> _moveLocation(Location source) async {
    if (_isActionInProgress) {
      return;
    }
    setState(() => _isActionInProgress = true);

    try {
      final target = await showModalBottomSheet<LocationMoveTarget>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => LocationTargetPicker(sourceId: source.id),
      );
      if (target == null || !mounted) {
        return;
      }

      final repository = ref.read(locationRepositoryProvider);
      final currentSource = await repository.getById(source.id);
      final oldPath = await repository.fullPath(source.id);
      final targetPath = target.parentId == null
          ? '我的收纳位置'
          : await repository.fullPath(target.parentId!);
      final newPath = target.parentId == null
          ? currentSource.name
          : '$targetPath / ${currentSource.name}';
      final impact = await _loadMoveImpact(currentSource.id);
      if (!mounted) {
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认移动位置'),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                const Text('源位置'),
                Text(oldPath),
                const SizedBox(height: 12),
                const Text('移动后路径'),
                Text(newPath),
                const SizedBox(height: 12),
                Text('包含子位置：${impact.descendantLocationCount} 个'),
                Text('包含物品：${impact.itemCount} 条'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认移动'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }

      final moved = await repository.move(
        id: currentSource.id,
        targetParentId: target.parentId,
      );
      if (!mounted) {
        return;
      }
      if (!moved) {
        _showMessage('目标就是当前上级位置，未发生变化');
        return;
      }

      ref.invalidate(locationChildrenProvider(currentSource.parentId));
      ref.invalidate(locationChildrenProvider(target.parentId));
      final movedPath = await _loadPathToLocation(currentSource.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _currentLocationId = currentSource.id;
        _breadcrumbs
          ..clear()
          ..addAll(movedPath);
      });
      ref.invalidate(locationChildrenProvider(currentSource.id));
      ref.invalidate(locationDirectItemsProvider(currentSource.id));
      _showMessage('位置已移动');
    } catch (error) {
      if (mounted) {
        _showMessage(_friendlyError(error, fallback: '移动位置失败，请重试'));
      }
    } finally {
      if (mounted) {
        setState(() => _isActionInProgress = false);
      }
    }
  }

  Future<void> _deleteLocation(Location location) async {
    if (_isActionInProgress) {
      return;
    }
    setState(() => _isActionInProgress = true);

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除收纳位置'),
          content: Text(
            '确定删除“${location.name}”吗？\n\n'
            '只有没有子位置、没有直接物品的空位置才能删除。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认删除'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }

      await ref.read(locationRepositoryProvider).deleteEmpty(location.id);
      ref.invalidate(locationChildrenProvider(location.parentId));
      if (location.id == _currentLocationId) {
        _goUp();
      }
      _showMessage('位置已删除');
    } catch (error) {
      if (mounted) {
        _showMessage(_friendlyError(error, fallback: '删除位置失败，请重试'));
      }
    } finally {
      if (mounted) {
        setState(() => _isActionInProgress = false);
      }
    }
  }

  Future<void> _refreshCurrentLevel() async {
    final childrenProvider = locationChildrenProvider(_currentLocationId);
    ref.invalidate(childrenProvider);
    final futures = <Future<void>>[
      ref.read(childrenProvider.future).then((_) {}),
    ];

    final currentLocationId = _currentLocationId;
    if (currentLocationId != null) {
      final itemsProvider = locationDirectItemsProvider(currentLocationId);
      ref.invalidate(itemsProvider);
      futures.add(ref.read(itemsProvider.future).then((_) {}));
    }
    await Future.wait(futures);
  }

  Future<List<Location>> _loadPathToLocation(int locationId) async {
    final repository = ref.read(locationRepositoryProvider);
    final path = <Location>[];
    final visited = <int>{};
    Location? current = await repository.getById(locationId);
    while (current != null) {
      if (!visited.add(current.id)) {
        throw const LocationRepositoryException(
          LocationRepositoryErrorCode.cycleMove,
          '收纳位置存在循环引用',
        );
      }
      path.insert(0, current);
      current = current.parentId == null
          ? null
          : await repository.getById(current.parentId!);
    }
    return path;
  }

  Future<String> _pathForLocation(int locationId) {
    return ref.read(locationRepositoryProvider).fullPath(locationId);
  }

  Future<_MoveImpact> _loadMoveImpact(int sourceId) async {
    final locationRepository = ref.read(locationRepositoryProvider);
    final itemRepository = ref.read(itemRepositoryProvider);
    final impact = _MoveImpact();
    final visited = <int>{};

    Future<void> visit(int locationId) async {
      if (!visited.add(locationId)) {
        throw const LocationRepositoryException(
          LocationRepositoryErrorCode.cycleMove,
          '收纳位置存在循环引用',
        );
      }
      final children = await locationRepository.listChildren(locationId);
      impact.descendantLocationCount += children.length;
      impact.itemCount += (await itemRepository.listByLocation(locationId))
          .length;
      for (final child in children) {
        await visit(child.id);
      }
    }

    await visit(sourceId);
    return impact;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _friendlyError(Object error, {required String fallback}) {
    if (error is LocationRepositoryException) {
      if (error.code == LocationRepositoryErrorCode.notEmpty) {
        return '该位置仍包含子位置或物品，无法删除';
      }
      return error.message;
    }
    return fallback;
  }
}

class _MoveImpact {
  int descendantLocationCount = 0;
  int itemCount = 0;
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty({required this.text, this.icon = Icons.inbox_outlined});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 36,
              color: theme.colorScheme.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          const Icon(Icons.error_outline),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
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

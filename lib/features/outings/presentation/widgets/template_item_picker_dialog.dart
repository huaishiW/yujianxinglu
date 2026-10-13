import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/local/app_database.dart';
import '../../../items/application/item_providers.dart';

class SelectedItemResult {
  const SelectedItemResult({required this.item, required this.locationPath});

  final Item item;
  final String locationPath;
}

class TemplateItemPickerDialog extends ConsumerStatefulWidget {
  const TemplateItemPickerDialog({required this.excludedItemIds, super.key});

  final Set<int> excludedItemIds;

  static Future<SelectedItemResult?> show(
    BuildContext context, {
    required Set<int> excludedItemIds,
  }) {
    return showModalBottomSheet<SelectedItemResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          TemplateItemPickerDialog(excludedItemIds: excludedItemIds),
    );
  }

  @override
  ConsumerState<TemplateItemPickerDialog> createState() =>
      _TemplateItemPickerDialogState();
}

class _TemplateItemPickerDialogState
    extends ConsumerState<TemplateItemPickerDialog> {
  final _searchController = TextEditingController();
  String _keyword = '';
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          _keyword = query;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final searchResults = ref.watch(itemSearchProvider(_keyword));

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: '搜索要添加的登记物品...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _debounceTimer?.cancel();
                                  _searchController.clear();
                                  setState(() => _keyword = '');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        isDense: true,
                      ),
                      onChanged: _onQueryChanged,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: searchResults.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('读取物品列表失败'),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () =>
                            ref.invalidate(itemSearchProvider(_keyword)),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return Center(
                      child: Text(
                        _keyword.trim().isEmpty ? '物品库中暂无物品' : '未找到匹配的物品',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: items.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final isAlreadyAdded = widget.excludedItemIds.contains(
                        item.id,
                      );

                      return _ItemPickerTile(
                        item: item,
                        isAlreadyAdded: isAlreadyAdded,
                        onSelected: (path) {
                          Navigator.of(context).pop(
                            SelectedItemResult(item: item, locationPath: path),
                          );
                        },
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
}

class _ItemPickerTile extends ConsumerWidget {
  const _ItemPickerTile({
    required this.item,
    required this.isAlreadyAdded,
    required this.onSelected,
  });

  final Item item;
  final bool isAlreadyAdded;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pathAsync = ref.watch(locationPathProvider(item.locationId));
    final pathText = pathAsync.value ?? '加载位置中...';

    return Card(
      margin: EdgeInsets.zero,
      color: isAlreadyAdded
          ? Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5)
          : null,
      child: ListTile(
        enabled: !isAlreadyAdded,
        leading: CircleAvatar(
          backgroundColor: isAlreadyAdded ? Colors.grey.shade300 : null,
          child: Icon(
            isAlreadyAdded ? Icons.check : Icons.inventory_2_outlined,
            color: isAlreadyAdded ? Colors.grey : null,
          ),
        ),
        title: Text(
          item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isAlreadyAdded ? Colors.grey : null,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              '库存：${item.quantity} 件 | 位置：$pathText',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: isAlreadyAdded ? Colors.grey : null),
            ),
            if (isAlreadyAdded)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text(
                  '已在当前模板中（禁止重复添加）',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
          ],
        ),
        trailing: isAlreadyAdded
            ? null
            : FilledButton.tonal(
                onPressed: () => onSelected(pathText),
                child: const Text('选择'),
              ),
        onTap: isAlreadyAdded ? null : () => onSelected(pathText),
      ),
    );
  }
}

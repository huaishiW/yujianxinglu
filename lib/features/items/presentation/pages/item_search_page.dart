import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/local/app_database.dart';
import '../../application/item_providers.dart';

class ItemSearchPage extends ConsumerStatefulWidget {
  const ItemSearchPage({super.key});

  @override
  ConsumerState<ItemSearchPage> createState() => _ItemSearchPageState();
}

class _ItemSearchPageState extends ConsumerState<ItemSearchPage> {
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

  void _clearSearch() {
    _debounceTimer?.cancel();
    _searchController.clear();
    setState(() {
      _keyword = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final searchResults = ref.watch(itemSearchProvider(_keyword));

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '搜索物品名称...',
            border: InputBorder.none,
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: _clearSearch,
                    tooltip: '清除',
                  )
                : null,
          ),
          onChanged: _onQueryChanged,
        ),
      ),
      body: SafeArea(
        child: searchResults.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                const Text('搜索失败，请重试'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(itemSearchProvider(_keyword)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
          data: (items) {
            if (items.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.search_off_outlined,
                      size: 64,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _keyword.trim().isEmpty
                          ? '物品库中暂无物品'
                          : '未找到名称包含“${_keyword.trim()}”的物品',
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                return _SearchResultCard(item: item);
              },
            );
          },
        ),
      ),
    );
  }
}

class _SearchResultCard extends ConsumerWidget {
  const _SearchResultCard({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pathAsync = ref.watch(locationPathProvider(item.locationId));

    return Card(
      key: ValueKey('search-item-${item.id}'),
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
        title: Text(
          item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('数量：${item.quantity}'),
            const SizedBox(height: 2),
            pathAsync.when(
              loading: () => const Text('位置：加载中...'),
              error: (err, stack) => const Text('位置：未知'),
              data: (path) => Text(
                '位置：$path',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          context.push('/items/${item.id}');
        },
      ),
    );
  }
}

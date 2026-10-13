import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/item_providers.dart';
import '../widgets/item_delete_dialog.dart';

class ItemDetailPage extends ConsumerWidget {
  const ItemDetailPage({required this.itemId, super.key});

  final int itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(itemDetailProvider(itemId));
    final pathAsync = ref.watch(itemLocationPathProvider(itemId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('物品详情'),
        actions: [
          itemAsync.maybeWhen(
            data: (item) => IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑物品',
              onPressed: () {
                context.push('/items/$itemId/edit');
              },
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          itemAsync.maybeWhen(
            data: (item) => IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除物品',
              onPressed: () async {
                final deleted = await ItemDeleteDialog.show(context, itemId);
                if (deleted == true && context.mounted) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(content: Text('已删除物品“${item.name}”')),
                    );
                  context.pop();
                }
              },
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: SafeArea(
        child: itemAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                const Text('物品不存在或已被删除'),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => context.pop(),
                  child: const Text('返回'),
                ),
              ],
            ),
          ),
          data: (item) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const CircleAvatar(child: Icon(Icons.inventory_2)),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '物品 ID: ${item.id}',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        _buildInfoRow(
                          context,
                          icon: Icons.numbers_outlined,
                          label: '存放数量',
                          value: '${item.quantity}',
                        ),
                        const SizedBox(height: 12),
                        pathAsync.when(
                          loading: () => _buildInfoRow(
                            context,
                            icon: Icons.place_outlined,
                            label: '收纳位置',
                            value: '正在加载路径...',
                          ),
                          error: (err, stack) => _buildInfoRow(
                            context,
                            icon: Icons.place_outlined,
                            label: '收纳位置',
                            value: '位置加载失败',
                          ),
                          data: (path) => _buildInfoRow(
                            context,
                            icon: Icons.place_outlined,
                            label: '收纳位置',
                            value: path,
                          ),
                        ),
                        if (item.category != null &&
                            item.category!.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _buildInfoRow(
                            context,
                            icon: Icons.category_outlined,
                            label: '分类',
                            value: item.category!,
                          ),
                        ],
                        if (item.note != null &&
                            item.note!.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _buildInfoRow(
                            context,
                            icon: Icons.notes_outlined,
                            label: '备注',
                            value: item.note!,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildInfoRow(
                          context,
                          icon: Icons.schedule_outlined,
                          label: '创建时间',
                          value: _formatTimestamp(item.createdAt),
                        ),
                        const SizedBox(height: 8),
                        _buildInfoRow(
                          context,
                          icon: Icons.update_outlined,
                          label: '最近更新',
                          value: _formatTimestamp(item.updatedAt),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _formatTimestamp(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        Expanded(
          child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ],
    );
  }
}

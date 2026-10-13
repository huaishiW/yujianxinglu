import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../data/repositories/item_repository.dart';
import '../../application/location_providers.dart';

class ItemDeleteDialog extends ConsumerStatefulWidget {
  const ItemDeleteDialog({required this.itemId, super.key});

  final int itemId;

  static Future<bool?> show(BuildContext context, int itemId) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ItemDeleteDialog(itemId: itemId),
    );
  }

  @override
  ConsumerState<ItemDeleteDialog> createState() => _ItemDeleteDialogState();
}

class _ItemDeleteDialogState extends ConsumerState<ItemDeleteDialog> {
  bool _isLoadingImpact = true;
  bool _isDeleting = false;
  ItemDeletionImpact? _impact;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadImpact();
  }

  Future<void> _loadImpact() async {
    try {
      final impact = await ref
          .read(itemRepositoryProvider)
          .queryDeletionImpact(widget.itemId);
      if (mounted) {
        setState(() {
          _impact = impact;
          _isLoadingImpact = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e is ItemRepositoryException ? e.message : '查询删除影响失败';
          _isLoadingImpact = false;
        });
      }
    }
  }

  Future<void> _confirmDelete() async {
    if (_isDeleting) return;
    setState(() => _isDeleting = true);

    try {
      await ref.read(itemRepositoryProvider).deleteById(widget.itemId);
      ref.read(locationBrowserRefreshProvider.notifier).refresh();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e is ItemRepositoryException ? e.message : '删除失败，请重试';
          _isDeleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoadingImpact) {
      return const AlertDialog(
        title: Text('检查物品关联...'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在检查模板和清单的引用情况'),
          ],
        ),
      );
    }

    final impact = _impact;
    if (impact == null) {
      return AlertDialog(
        title: const Text('无法获取物品信息'),
        content: Text(_errorMessage ?? '该物品可能已被删除'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('返回'),
          ),
        ],
      );
    }

    final hasRefs = impact.hasReferences;
    final item = impact.item;

    return AlertDialog(
      title: const Text('删除物品确认'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('确定要删除“${item.name}”（共 ${item.quantity} 件）吗？'),
            const SizedBox(height: 12),
            if (!hasRefs)
              const Text('该物品未被任何出门模板或任务引用，删除后记录将直接移除。')
            else ...[
              Text(
                '此物品已被以下内容引用：',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              if (impact.templateReferences.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                  child: Text('• 出门模板：${impact.templateReferences.length} 个条目'),
                ),
              if (impact.inProgressReferences.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                  child: Text(
                    '• 进行中清单：${impact.inProgressReferences.length} 个条目',
                  ),
                ),
              if (impact.completedReferences.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                  child: Text(
                    '• 已完成历史：${impact.completedReferences.length} 条记录',
                  ),
                ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '删除影响说明：',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '1. 原登记物品将被删除。\n'
                      '2. 相关模板和进行中清单的条目仍会保留，并自动转换为普通文本条目（保留名称、携带数量、勾选状态等）。\n'
                      '3. 已完成任务的历史快照保持不变。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isDeleting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _isDeleting ? null : _confirmDelete,
          child: _isDeleting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('确认删除'),
        ),
      ],
    );
  }
}

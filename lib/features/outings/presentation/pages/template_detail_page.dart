import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/repositories/template_repository.dart';
import '../../application/template_providers.dart';
import '../widgets/create_from_template_dialog.dart';
import '../widgets/template_delete_dialog.dart';

class TemplateDetailPage extends ConsumerWidget {
  const TemplateDetailPage({required this.templateId, super.key});

  final int templateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(templateDetailProvider(templateId));
    final shortagesAsync = ref.watch(templateShortagesProvider(templateId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('模板详情'),
        actions: [
          detailAsync.maybeWhen(
            data: (detail) => IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑模板',
              onPressed: () {
                context.push('/outings/templates/$templateId/edit');
              },
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          detailAsync.maybeWhen(
            data: (detail) => IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除模板',
              onPressed: () async {
                final deleted = await TemplateDeleteDialog.show(
                  context,
                  templateId: templateId,
                  templateName: detail.template.name,
                );
                if (deleted == true && context.mounted) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(content: Text('已删除模板“${detail.template.name}”')),
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
        child: detailAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                const Text('模板不存在或已被删除'),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => context.pop(),
                  child: const Text('返回'),
                ),
              ],
            ),
          ),
          data: (detail) {
            final template = detail.template;
            final entries = detail.entries;
            final shortages = shortagesAsync.value ?? [];
            final shortageMap = {for (final s in shortages) s.entry.id: s};

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              child: Icon(Icons.description_outlined),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    template.name,
                                    style: theme.textTheme.headlineSmall,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '模板 ID: ${template.id} | 条目总数: ${entries.length} 项',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (template.description != null &&
                            template.description!.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            template.description!,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (shortages.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withValues(
                        alpha: 0.7,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.colorScheme.error.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '库存不足提醒（共 ${shortages.length} 项数量不足）',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        for (final s in shortages)
                          Padding(
                            padding: const EdgeInsets.only(left: 4, top: 4),
                            child: Text(
                              '• ${s.item.name}：库存 ${s.currentQuantity}，需带 ${s.requiredQuantity}，缺少 ${s.shortage}',
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '模板清单条目',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < entries.length; i++) ...[
                  _buildEntryCard(
                    context,
                    detail: entries[i],
                    shortage: shortageMap[entries[i].entry.id],
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.directions_walk),
                    label: const Text('以此模板开始出门'),
                    onPressed: () async {
                      final sessionId = await CreateFromTemplateDialog.show(
                        context,
                        templateId: templateId,
                        templateName: detail.template.name,
                      );
                      if (sessionId != null && context.mounted) {
                        context.push('/outings/sessions/$sessionId');
                      }
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildEntryCard(
    BuildContext context, {
    required TemplateEntryDetail detail,
    TemplateQuantityShortage? shortage,
  }) {
    final theme = Theme.of(context);
    final entry = detail.entry;
    final isRegistered = detail.isRegisteredItem;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: shortage != null
            ? BorderSide(color: theme.colorScheme.error, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  labelStyle: const TextStyle(fontSize: 11),
                  avatar: Icon(
                    isRegistered
                        ? Icons.inventory_2_outlined
                        : Icons.text_fields_outlined,
                    size: 14,
                  ),
                  label: Text(isRegistered ? '已登记物品' : '普通文本'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    detail.displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '需带: ${entry.requiredQuantity}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            if (isRegistered) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.place_outlined,
                    size: 16,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '位置：${detail.locationPath ?? "未知位置"}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (detail.registeredItem != null)
                    Text(
                      '当前库存: ${detail.registeredItem!.quantity}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ],
            if (shortage != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '库存 ${shortage.currentQuantity}，需带 ${shortage.requiredQuantity}，缺少 ${shortage.shortage}',
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

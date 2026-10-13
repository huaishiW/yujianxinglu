import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../data/repositories/session_repository.dart';
import '../../application/session_providers.dart';
import '../widgets/session_complete_dialog.dart';
import '../widgets/session_delete_dialog.dart';

class SessionDetailPage extends ConsumerStatefulWidget {
  const SessionDetailPage({required this.sessionId, super.key});

  final int sessionId;

  @override
  ConsumerState<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends ConsumerState<SessionDetailPage> {
  final Set<int> _togglingEntryIds = <int>{};

  Future<void> _handleToggleCheck(SessionEntryDetail detail) async {
    final entryId = detail.entry.id;
    if (_togglingEntryIds.contains(entryId)) return;
    _togglingEntryIds.add(entryId);

    final newValue = !detail.isChecked;
    try {
      await ref
          .read(sessionRepositoryProvider)
          .setChecked(widget.sessionId, entryId, newValue);
      ref.read(sessionRefreshProvider.notifier).refresh();
      ref.invalidate(activeSessionsProvider);
    } catch (e) {
      if (mounted) {
        ref.invalidate(sessionDetailProvider(widget.sessionId));
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                e is SessionRepositoryException ? e.message : '更新勾选状态失败，请重试',
              ),
            ),
          );
      }
    } finally {
      if (mounted) {
        _togglingEntryIds.remove(entryId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(sessionDetailProvider(widget.sessionId));
    final shortagesAsync = ref.watch(
      sessionShortagesProvider(widget.sessionId),
    );
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: detailAsync.maybeWhen(
          data: (detail) => Text(detail.session.title),
          orElse: () => const Text('出门任务'),
        ),
        actions: [
          detailAsync.maybeWhen(
            data: (detail) {
              if (detail.session.status != 'IN_PROGRESS') {
                return const SizedBox.shrink();
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: '编辑任务',
                    onPressed: () {
                      context.push(
                        '/outings/sessions/${widget.sessionId}/edit',
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: '删除任务',
                    onPressed: () async {
                      final deleted = await SessionDeleteDialog.show(
                        context,
                        sessionId: widget.sessionId,
                        sessionTitle: detail.session.title,
                      );
                      if (deleted == true && context.mounted) {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(
                              content: Text('已删除出门任务“${detail.session.title}”'),
                            ),
                          );
                        context.pop();
                      }
                    },
                  ),
                ],
              );
            },
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
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  '读取出门任务详情失败',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error is SessionRepositoryException
                      ? error.message
                      : '$error',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () =>
                      ref.invalidate(sessionDetailProvider(widget.sessionId)),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
          data: (detail) {
            final session = detail.session;
            final isCompleted = session.status == 'COMPLETED';
            final entries = detail.entries;
            final totalCount = entries.length;
            final checkedCount = detail.checkedCount;
            final shortages =
                shortagesAsync.value ?? const <SessionQuantityShortage>[];
            final shortageMap = {for (final s in shortages) s.entry.id: s};

            final progress = totalCount == 0 ? 0.0 : checkedCount / totalCount;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                // 顶部状态与进度概览卡片
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isCompleted
                                    ? theme.colorScheme.tertiaryContainer
                                    : theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isCompleted ? '已完成' : '进行中',
                                style: TextStyle(
                                  color: isCompleted
                                      ? theme.colorScheme.onTertiaryContainer
                                      : theme.colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '$checkedCount / $totalCount 已携带',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '完成度: ${(progress * 100).toInt()}%',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                            if (session.completedAt != null)
                              Text(
                                '完成时间: ${_formatTime(session.completedAt!)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 缺货警示提示栏
                if (!isCompleted && shortages.isNotEmpty) ...[
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
                    '清单条目',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // 条目清单
                for (var i = 0; i < entries.length; i++) ...[
                  _buildEntryCard(
                    context,
                    detail: entries[i],
                    shortage: shortageMap[entries[i].entry.id],
                    isCompleted: isCompleted,
                  ),
                  const SizedBox(height: 8),
                ],

                const SizedBox(height: 16),

                // 底部动作区
                if (!isCompleted)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('完成出门'),
                      onPressed: () async {
                        final unchecked = entries
                            .where((e) => !e.isChecked)
                            .toList();
                        final confirm = await SessionCompleteDialog.show(
                          context,
                          sessionTitle: session.title,
                          uncheckedEntries: unchecked,
                        );

                        if (confirm == true && context.mounted) {
                          try {
                            await ref
                                .read(sessionRepositoryProvider)
                                .complete(
                                  widget.sessionId,
                                  confirmedUnchecked: true,
                                );
                            ref.read(sessionRefreshProvider.notifier).refresh();
                            ref.invalidate(activeSessionsProvider);

                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  const SnackBar(
                                    content: Text('已完成本次出门任务！历史快照已冻结归档。'),
                                  ),
                                );
                              context.pop();
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    e is SessionRepositoryException
                                        ? e.message
                                        : '完成任务失败，请重试',
                                  ),
                                ),
                              );
                            }
                          }
                        }
                      },
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 20,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '本次出门任务已归档，历史快照处于只读保护状态。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                      ],
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
    required SessionEntryDetail detail,
    SessionQuantityShortage? shortage,
    required bool isCompleted,
  }) {
    final theme = Theme.of(context);
    final entry = detail.entry;
    final isChecked = detail.isChecked;

    return Card(
      elevation: isChecked ? 0 : 1,
      color: isChecked
          ? theme.colorScheme.surfaceContainerLow
          : theme.colorScheme.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isCompleted ? null : () => _handleToggleCheck(detail),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: isChecked,
                onChanged: isCompleted
                    ? null
                    : (_) => _handleToggleCheck(detail),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: detail.isRegisteredItem
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            detail.isRegisteredItem ? '登记物品' : '普通文本',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: detail.isRegisteredItem
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            detail.displayName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              decoration: isChecked
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: isChecked
                                  ? theme.colorScheme.outline
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          '需带: ${entry.requiredQuantity} 件',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isChecked
                                ? theme.colorScheme.outline
                                : theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (detail.isRegisteredItem) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 14,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              detail.locationPath ?? '收纳位置未记录',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                          if (detail.registeredItem != null)
                            Text(
                              '库存: ${detail.registeredItem!.quantity} 件',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (shortage != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
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
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$m-$d $h:$min';
  }
}

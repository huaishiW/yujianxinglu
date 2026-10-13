import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../data/local/app_database.dart';
import '../../../outings/application/session_providers.dart';
import '../../../outings/application/template_providers.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeSessions = ref.watch(activeSessionsProvider);
    final recentTemplates = ref.watch(recentTemplatesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('个人物品与出门助手'), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(sessionRefreshProvider.notifier).refresh();
          ref.read(templateRefreshProvider.notifier).refresh();
          ref.invalidate(activeSessionsProvider);
          ref.invalidate(recentTemplatesProvider);
          await Future.wait([
            ref.read(activeSessionsProvider.future),
            ref.read(recentTemplatesProvider.future),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // B1: 快速搜索入口
            TextField(
              readOnly: true,
              onTap: () {
                context.push('/items/search');
              },
              decoration: const InputDecoration(
                hintText: '搜索物品名称',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 20),

            // B2: 进行中的出门任务
            _SectionHeader(
              title: '进行中的出门任务',
              actionLabel: '查看全部',
              onAction: () => context.go('/outings'),
            ),
            const SizedBox(height: 8),
            activeSessions.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              ),
              error: (error, stackTrace) => _HomeError(
                message: '读取进行中的任务失败',
                onRetry: () {
                  ref.read(sessionRefreshProvider.notifier).refresh();
                  ref.invalidate(activeSessionsProvider);
                },
              ),
              data: (sessions) {
                if (sessions.isEmpty) {
                  return const _EmptyActiveSessionsCard();
                }
                return Column(
                  children: [
                    for (final session in sessions.take(3))
                      _ActiveSessionCard(session: session),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),

            // B3: 最近使用的模板
            _SectionHeader(
              title: '最近使用的模板',
              actionLabel: '全部模板',
              onAction: () => context.go('/outings'),
            ),
            const SizedBox(height: 8),
            recentTemplates.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              ),
              error: (error, stackTrace) => _HomeError(
                message: '读取最近使用模板失败',
                onRetry: () {
                  ref.read(templateRefreshProvider.notifier).refresh();
                  ref.invalidate(recentTemplatesProvider);
                },
              ),
              data: (templates) {
                if (templates.isEmpty) {
                  return const _EmptyRecentTemplatesCard();
                }
                return Column(
                  children: [
                    for (final template in templates.take(4))
                      _RecentTemplateCard(template: template),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(actionLabel),
              const SizedBox(width: 2),
              const Icon(Icons.arrow_forward_ios, size: 12),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActiveSessionCard extends ConsumerWidget {
  const _ActiveSessionCard({required this.session});

  final OutgoingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(sessionDetailProvider(session.id));
    final theme = Theme.of(context);

    return Card(
      key: ValueKey('home-active-session-${session.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/outings/sessions/${session.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      session.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '继续检查',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              detailAsync.when(
                loading: () => const LinearProgressIndicator(minHeight: 6),
                error: (_, _) => Text(
                  '读取进度失败',
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 13,
                  ),
                ),
                data: (detail) {
                  final total = detail.entries.length;
                  final checked = detail.checkedCount;
                  final unchecked = detail.uncheckedCount;
                  final progress = total == 0 ? 0.0 : checked / total;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            unchecked == 0 && total > 0
                                ? Colors.green
                                : theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$checked / $total 已准备',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            total == 0
                                ? '暂无条目'
                                : unchecked == 0
                                ? '全部就绪'
                                : '还剩 $unchecked 项未勾选',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: unchecked == 0 && total > 0
                                  ? Colors.green
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyActiveSessionsCard extends StatelessWidget {
  const _EmptyActiveSessionsCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.checklist_rtl_outlined,
                size: 44,
                color: theme.colorScheme.outline.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 10),
              Text(
                '当前没有进行中的出门任务',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '提前备齐随身物品，轻松从容出门',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => context.push('/outings/sessions/new'),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建本次出门'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentTemplateCard extends ConsumerWidget {
  const _RecentTemplateCard({required this.template});

  final OutgoingTemplate template;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(templateDetailProvider(template.id));
    final theme = Theme.of(context);

    return Card(
      key: ValueKey('home-recent-template-${template.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/outings/templates/${template.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.description_outlined,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        detailAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                          data: (detail) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              '${detail.entries.length} 项物品',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        if (template.lastUsedAt != null)
                          Text(
                            '上次使用: ${_formatTime(template.lastUsedAt!)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.outlineVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyRecentTemplatesCard extends StatelessWidget {
  const _EmptyRecentTemplatesCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.bookmark_border_outlined,
                size: 44,
                color: theme.colorScheme.outline.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 10),
              Text(
                '暂无最近使用的出门模板',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '将常用随身物品保存为模板，一键复用',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => context.push('/outings/templates/new'),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('创建出门模板'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeError extends StatelessWidget {
  const _HomeError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(message)),
        IconButton(
          onPressed: onRetry,
          tooltip: '重新加载',
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

String _formatTime(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  return '$m-$d $h:$min';
}

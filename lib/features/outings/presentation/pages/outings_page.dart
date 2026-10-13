import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../data/local/app_database.dart';
import '../../application/session_providers.dart';
import '../../application/template_providers.dart';
import '../widgets/session_delete_dialog.dart';
import '../widgets/template_delete_dialog.dart';

class OutingsPage extends ConsumerStatefulWidget {
  const OutingsPage({super.key});

  @override
  ConsumerState<OutingsPage> createState() => _OutingsPageState();
}

class _OutingsPageState extends ConsumerState<OutingsPage> {
  final _searchController = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeSessions = ref.watch(sessionListProvider);
    final templateListAsync = ref.watch(templateListProvider(_keyword));
    final recentTemplatesAsync = ref.watch(recentTemplatesProvider);
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('出门'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.checklist_outlined), text: '进行中'),
              Tab(icon: Icon(Icons.description_outlined), text: '模板'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: 进行中的任务
            Scaffold(
              body: RefreshIndicator(
                onRefresh: () async {
                  ref.read(sessionRefreshProvider.notifier).refresh();
                  ref.invalidate(activeSessionsProvider);
                  await ref.read(sessionListProvider.future);
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    const Text(
                      '进行中的任务',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    activeSessions.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (error, stackTrace) => _ErrorText(
                        message: '读取进行中的任务失败',
                        onRetry: () => ref.invalidate(sessionListProvider),
                      ),
                      data: (sessions) {
                        if (sessions.isEmpty) {
                          return const _EmptyText(text: '暂无进行中的任务，点击右下角创建');
                        }
                        return Column(
                          children: [
                            for (final session in sessions)
                              _SessionCard(
                                key: ValueKey('session-card-${session.id}'),
                                session: session,
                                onOpen: () => context.push(
                                  '/outings/sessions/${session.id}',
                                ),
                                onEdit: () => context.push(
                                  '/outings/sessions/${session.id}/edit',
                                ),
                                onDelete: () async {
                                  final deleted =
                                      await SessionDeleteDialog.show(
                                        context,
                                        sessionId: session.id,
                                        sessionTitle: session.title,
                                      );
                                  if (deleted == true && context.mounted) {
                                    ScaffoldMessenger.of(context)
                                      ..hideCurrentSnackBar()
                                      ..showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '已删除出门任务“${session.title}”',
                                          ),
                                        ),
                                      );
                                  }
                                },
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              floatingActionButton: FloatingActionButton.extended(
                key: const ValueKey('create-session-fab'),
                onPressed: () {
                  context.push('/outings/sessions/new');
                },
                icon: const Icon(Icons.add),
                label: const Text('新建任务'),
              ),
            ),

            // Tab 2: 出门模板管理
            Scaffold(
              body: RefreshIndicator(
                onRefresh: () async {
                  ref.read(templateRefreshProvider.notifier).refresh();
                  ref.invalidate(templateListProvider(_keyword));
                  ref.invalidate(recentTemplatesProvider);
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: '搜索出门模板名称...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _keyword = '');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        isDense: true,
                      ),
                      onChanged: (val) {
                        setState(() => _keyword = val.trim());
                      },
                    ),
                    if (_keyword.isEmpty) ...[
                      recentTemplatesAsync.when(
                        data: (recentList) {
                          if (recentList.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 16),
                              Text(
                                '最近使用的模板',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final template in recentList)
                                    ActionChip(
                                      avatar: const Icon(
                                        Icons.history,
                                        size: 16,
                                      ),
                                      label: Text(template.name),
                                      onPressed: () {
                                        context.push(
                                          '/outings/templates/${template.id}',
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ],
                          );
                        },
                        loading: () => const SizedBox.shrink(),
                        error: (err, stack) => const SizedBox.shrink(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _keyword.isEmpty ? '所有模板' : '搜索结果',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        templateListAsync.maybeWhen(
                          data: (list) => Text(
                            '共 ${list.length} 个',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          orElse: () => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    templateListAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (error, stack) => _ErrorText(
                        message: '读取出门模板失败，请重试',
                        onRetry: () =>
                            ref.invalidate(templateListProvider(_keyword)),
                      ),
                      data: (templates) {
                        if (templates.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 48),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.description_outlined,
                                    size: 48,
                                    color: theme.colorScheme.outline,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _keyword.isEmpty
                                        ? '暂无出门模板，点击右下角创建'
                                        : '未找到名称包含“$_keyword”的模板',
                                    style: TextStyle(
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return Column(
                          children: [
                            for (final template in templates)
                              _TemplateCard(
                                key: ValueKey('template-card-${template.id}'),
                                template: template,
                                onOpen: () {
                                  context.push(
                                    '/outings/templates/${template.id}',
                                  );
                                },
                                onEdit: () {
                                  context.push(
                                    '/outings/templates/${template.id}/edit',
                                  );
                                },
                                onDelete: () async {
                                  final deleted =
                                      await TemplateDeleteDialog.show(
                                        context,
                                        templateId: template.id,
                                        templateName: template.name,
                                      );
                                  if (deleted == true && context.mounted) {
                                    ScaffoldMessenger.of(context)
                                      ..hideCurrentSnackBar()
                                      ..showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '已删除模板“${template.name}”',
                                          ),
                                        ),
                                      );
                                  }
                                },
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              floatingActionButton: FloatingActionButton.extended(
                key: const ValueKey('create-template-fab'),
                onPressed: () {
                  context.push('/outings/templates/new');
                },
                icon: const Icon(Icons.add),
                label: const Text('新建模板'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionCard extends ConsumerWidget {
  const _SessionCard({
    required this.session,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final OutgoingSession session;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(sessionDetailProvider(session.id));
    final shortagesAsync = ref.watch(sessionShortagesProvider(session.id));
    final theme = Theme.of(context);

    final detail = detailAsync.value;
    final totalCount = detail?.entries.length ?? 0;
    final checkedCount = detail?.checkedCount ?? 0;
    final shortageCount = shortagesAsync.value?.length ?? 0;
    final progress = totalCount == 0 ? 0.0 : checkedCount / totalCount;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: shortageCount > 0
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.primaryContainer,
          child: Icon(
            shortageCount > 0
                ? Icons.warning_amber_rounded
                : Icons.checklist_outlined,
            color: shortageCount > 0
                ? theme.colorScheme.error
                : theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          session.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  detail == null ? '加载中...' : '$checkedCount / $totalCount 已携带',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (shortageCount > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '⚠️ $shortageCount 项缺货',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '更新于: ${_formatTime(session.updatedAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑',
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: onDelete,
            ),
          ],
        ),
        onTap: onOpen,
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

class _TemplateCard extends ConsumerWidget {
  const _TemplateCard({
    required this.template,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final OutgoingTemplate template;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(templateDetailProvider(template.id));
    final shortagesAsync = ref.watch(templateShortagesProvider(template.id));
    final theme = Theme.of(context);

    final entryCount = detailAsync.value?.entries.length;
    final shortageCount = shortagesAsync.value?.length ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: shortageCount > 0
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.primaryContainer,
          child: Icon(
            shortageCount > 0
                ? Icons.warning_amber_rounded
                : Icons.description_outlined,
            color: shortageCount > 0
                ? theme.colorScheme.error
                : theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          template.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  entryCount == null ? '条目读取中...' : '$entryCount 个条目',
                  style: theme.textTheme.bodySmall,
                ),
                if (shortageCount > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '⚠️ $shortageCount 项缺货',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
            if (template.lastUsedAt != null)
              Text(
                '最近使用: ${_formatTime(template.lastUsedAt!)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑',
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: onDelete,
            ),
          ],
        ),
        onTap: onOpen,
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

class _EmptyText extends StatelessWidget {
  const _EmptyText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(text),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.message, required this.onRetry});

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

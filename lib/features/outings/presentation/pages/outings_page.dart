import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';

class OutingsPage extends ConsumerWidget {
  const OutingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeSessions = ref.watch(activeSessionsProvider);
    final templates = ref.watch(templatesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('出门')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Text(
            '进行中的任务',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          activeSessions.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => _ErrorText(
              message: '读取进行中的任务失败',
              onRetry: () => ref.invalidate(activeSessionsProvider),
            ),
            data: (sessions) {
              if (sessions.isEmpty) {
                return const _EmptyText(text: '暂无进行中的任务');
              }
              return Column(
                children: [
                  for (final session in sessions)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.checklist_outlined),
                      title: Text(session.title),
                      subtitle: const Text('进行中'),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          const Text(
            '出门模板',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          templates.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => _ErrorText(
              message: '读取出门模板失败',
              onRetry: () => ref.invalidate(templatesProvider),
            ),
            data: (templateList) {
              if (templateList.isEmpty) {
                return const _EmptyText(text: '暂无出门模板');
              }
              return Column(
                children: [
                  for (final template in templateList)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.description_outlined),
                      title: Text(template.name),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          const Text(
            '模板编辑和任务操作将在后续阶段接入',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/app_providers.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeSessions = ref.watch(activeSessionsProvider);
    final recentTemplates = ref.watch(recentTemplatesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('个人物品与出门助手'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          TextField(
            readOnly: true,
            onTap: () {
              context.push('/items/search');
            },
            decoration: const InputDecoration(
              labelText: '搜索物品名称',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '进行中的出门任务',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          activeSessions.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => _HomeError(
              message: '读取进行中的任务失败',
              onRetry: () => ref.invalidate(activeSessionsProvider),
            ),
            data: (sessions) {
              if (sessions.isEmpty) {
                return const _HomeEmpty(text: '暂无进行中的任务');
              }
              return Column(
                children: [
                  for (final session in sessions.take(3))
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
            '最近使用的模板',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          recentTemplates.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => _HomeError(
              message: '读取最近使用模板失败',
              onRetry: () => ref.invalidate(recentTemplatesProvider),
            ),
            data: (templates) {
              if (templates.isEmpty) {
                return const _HomeEmpty(text: '暂无最近使用的模板');
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final template in templates)
                    Chip(
                      avatar: const Icon(Icons.description_outlined, size: 18),
                      label: Text(template.name),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HomeEmpty extends StatelessWidget {
  const _HomeEmpty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(text),
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

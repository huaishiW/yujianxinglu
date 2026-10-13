import 'package:flutter/material.dart';

import '../../../../data/repositories/session_repository.dart';

class SessionCompleteDialog extends StatelessWidget {
  const SessionCompleteDialog({
    required this.sessionTitle,
    required this.uncheckedEntries,
    super.key,
  });

  final String sessionTitle;
  final List<SessionEntryDetail> uncheckedEntries;

  static Future<bool?> show(
    BuildContext context, {
    required String sessionTitle,
    required List<SessionEntryDetail> uncheckedEntries,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => SessionCompleteDialog(
        sessionTitle: sessionTitle,
        uncheckedEntries: uncheckedEntries,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUnchecked = uncheckedEntries.isNotEmpty;

    if (!hasUnchecked) {
      return AlertDialog(
        title: const Text('完成出门任务'),
        content: Text(
          '“$sessionTitle”的所有条目均已勾选完毕。\n\n确认完成本次出门吗？完成后将冻结历史快照并归档为只读记录。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认完成'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          const Text('仍有未勾选条目'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '还有 ${uncheckedEntries.length} 项未勾选，确定仍要完成本次出门吗？',
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '未勾选条目清单：',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            for (final entry in uncheckedEntries)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text(
                  '• ${entry.displayName}（需带 ${entry.entry.requiredQuantity} 件）',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            const SizedBox(height: 10),
            Text(
              '提示：点击“仍要完成”后，未勾选项仍会保留未勾选状态归档在历史记录中，不会自动补全勾选。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('返回检查'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('仍要完成'),
        ),
      ],
    );
  }
}

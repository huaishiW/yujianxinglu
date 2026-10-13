import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../data/repositories/session_repository.dart';
import '../../application/session_providers.dart';

class SessionDeleteDialog extends ConsumerStatefulWidget {
  const SessionDeleteDialog({
    required this.sessionId,
    required this.sessionTitle,
    super.key,
  });

  final int sessionId;
  final String sessionTitle;

  static Future<bool?> show(
    BuildContext context, {
    required int sessionId,
    required String sessionTitle,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) =>
          SessionDeleteDialog(sessionId: sessionId, sessionTitle: sessionTitle),
    );
  }

  @override
  ConsumerState<SessionDeleteDialog> createState() =>
      _SessionDeleteDialogState();
}

class _SessionDeleteDialogState extends ConsumerState<SessionDeleteDialog> {
  bool _isDeleting = false;
  String? _errorMessage;

  Future<void> _confirmDelete() async {
    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(sessionRepositoryProvider);
      await repo.deleteActiveConfirmed(widget.sessionId);
      ref.read(sessionRefreshProvider.notifier).refresh();
      ref.invalidate(activeSessionsProvider);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDeleting = false;
          _errorMessage = e is SessionRepositoryException
              ? e.message
              : '删除任务失败，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.delete_outline, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          const Text('删除出门任务'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '确定要删除进行中的任务“${widget.sessionTitle}”吗？',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(
            '• 该任务及其包含的条目将被永久删除；',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '• 不会删除物品库中关联的登记物品；',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '• 不会影响原始出门模板及其他任务；',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '• 此操作无法撤销。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
            ),
          ],
        ],
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
                  width: 18,
                  height: 18,
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

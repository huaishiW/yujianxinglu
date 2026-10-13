import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../data/repositories/template_repository.dart';
import '../../application/template_providers.dart';

class TemplateDeleteDialog extends ConsumerStatefulWidget {
  const TemplateDeleteDialog({
    required this.templateId,
    required this.templateName,
    super.key,
  });

  final int templateId;
  final String templateName;

  static Future<bool?> show(
    BuildContext context, {
    required int templateId,
    required String templateName,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => TemplateDeleteDialog(
        templateId: templateId,
        templateName: templateName,
      ),
    );
  }

  @override
  ConsumerState<TemplateDeleteDialog> createState() =>
      _TemplateDeleteDialogState();
}

class _TemplateDeleteDialogState extends ConsumerState<TemplateDeleteDialog> {
  bool _isDeleting = false;
  String? _errorMessage;

  Future<void> _confirmDelete() async {
    if (_isDeleting) return;
    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(templateRepositoryProvider).deleteById(widget.templateId);
      ref.read(templateRefreshProvider.notifier).refresh();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e is TemplateRepositoryException
              ? e.message
              : '删除模板失败，请重试';
          _isDeleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('删除出门模板'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('确定要删除模板“${widget.templateName}”吗？'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '删除影响说明：',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('• 该模板及其包含的条目将被永久删除；'),
                  const Text('• 不会删除物品库中关联的登记物品；'),
                  const Text('• 不会删除已生成的出门任务与历史记录。'),
                ],
              ),
            ),
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

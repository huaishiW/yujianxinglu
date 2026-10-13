import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../data/repositories/session_repository.dart';
import '../../application/session_providers.dart';
import '../../application/template_providers.dart';

class CreateFromTemplateDialog extends ConsumerStatefulWidget {
  const CreateFromTemplateDialog({
    required this.templateId,
    required this.templateName,
    super.key,
  });

  final int templateId;
  final String templateName;

  static Future<int?> show(
    BuildContext context, {
    required int templateId,
    required String templateName,
  }) {
    return showDialog<int>(
      context: context,
      builder: (context) => CreateFromTemplateDialog(
        templateId: templateId,
        templateName: templateName,
      ),
    );
  }

  @override
  ConsumerState<CreateFromTemplateDialog> createState() =>
      _CreateFromTemplateDialogState();
}

class _CreateFromTemplateDialogState
    extends ConsumerState<CreateFromTemplateDialog> {
  late final TextEditingController _titleController;
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.templateName);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final title = _titleController.text.trim();

    try {
      final sessionRepo = ref.read(sessionRepositoryProvider);
      final sessionId = await sessionRepo.createFromTemplate(
        widget.templateId,
        title: title,
      );

      ref.read(sessionRefreshProvider.notifier).refresh();
      ref.read(templateRefreshProvider.notifier).refresh();
      ref.invalidate(recentTemplatesProvider);
      ref.invalidate(activeSessionsProvider);

      if (mounted) {
        Navigator.of(context).pop(sessionId);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e is SessionRepositoryException
              ? e.message
              : '创建出门任务失败，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('开始本次出门'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '将基于模板“${widget.templateName}”创建全新的出门任务，全部条目初始为未勾选。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '本次出门名称 *',
                hintText: '如：日常通勤、周末野餐',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '出门名称不能为空';
                }
                return null;
              },
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('开始出门'),
        ),
      ],
    );
  }
}

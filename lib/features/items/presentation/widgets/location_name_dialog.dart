import 'package:flutter/material.dart';

class LocationNameDialog extends StatefulWidget {
  const LocationNameDialog({
    required this.title,
    required this.onSubmit,
    this.initialName = '',
    this.parentPath,
    super.key,
  });

  final String title;
  final String initialName;
  final String? parentPath;
  final Future<void> Function(String name) onSubmit;

  @override
  State<LocationNameDialog> createState() => _LocationNameDialogState();
}

class _LocationNameDialogState extends State<LocationNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  String? _errorMessage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.parentPath != null) ...[
              Text(
                '上级位置：${widget.parentPath}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _nameController,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: '位置名称'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '位置名称不能为空';
                }
                return null;
              },
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() => _errorMessage = null);
                }
              },
              onFieldSubmitted: _isSaving ? null : (_) => _submit(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _errorMessage = null;
      _isSaving = true;
    });

    try {
      await widget.onSubmit(_nameController.text.trim());
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error is Exception
              ? error.toString()
              : '保存收纳位置失败，请重试';
          _isSaving = false;
        });
      }
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../data/repositories/session_repository.dart';
import '../../application/session_providers.dart';
import '../widgets/template_item_picker_dialog.dart';

class _SessionEntryDraft {
  _SessionEntryDraft({
    this.id,
    required this.itemType,
    this.itemId,
    this.textName,
    required this.displayName,
    this.locationPath,
    this.currentStock,
    this.requiredQuantity = 1,
  });

  final int? id;
  final String itemType;
  final int? itemId;
  String? textName;
  String displayName;
  String? locationPath;
  int? currentStock;
  int requiredQuantity;

  bool get isRegisteredItem => itemType == registeredSessionItemType;
  bool get isShortage =>
      isRegisteredItem &&
      currentStock != null &&
      requiredQuantity > currentStock!;
}

class SessionEditPage extends ConsumerStatefulWidget {
  const SessionEditPage({this.sessionId, super.key});

  final int? sessionId;

  bool get isEditing => sessionId != null;

  @override
  ConsumerState<SessionEditPage> createState() => _SessionEditPageState();
}

class _SessionEditPageState extends ConsumerState<SessionEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;

  final List<_SessionEntryDraft> _draftEntries = [];
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    if (widget.isEditing) {
      _loadSessionData();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadSessionData() async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(sessionRepositoryProvider);
      final detail = await repo.getDetail(widget.sessionId!);
      if (detail.session.status != 'IN_PROGRESS') {
        throw const SessionRepositoryException(
          SessionRepositoryErrorCode.completedSessionReadOnly,
          '已完成出门任务为只读，不能修改',
        );
      }

      _titleController.text = detail.session.title;
      _draftEntries.clear();
      for (final entryDetail in detail.entries) {
        _draftEntries.add(
          _SessionEntryDraft(
            id: entryDetail.entry.id,
            itemType: entryDetail.entry.itemType,
            itemId: entryDetail.entry.itemId,
            textName: entryDetail.entry.textName,
            displayName: entryDetail.displayName,
            locationPath: entryDetail.locationPath,
            currentStock: entryDetail.registeredItem?.quantity,
            requiredQuantity: entryDetail.entry.requiredQuantity,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e is SessionRepositoryException
              ? e.message
              : '加载出门任务数据失败';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _addRegisteredItem() async {
    final excludedIds = _draftEntries
        .where((e) => e.itemId != null)
        .map((e) => e.itemId!)
        .toSet();

    final result = await TemplateItemPickerDialog.show(
      context,
      excludedItemIds: excludedIds,
    );

    if (result != null && mounted) {
      setState(() {
        _draftEntries.add(
          _SessionEntryDraft(
            id: null,
            itemType: registeredSessionItemType,
            itemId: result.item.id,
            displayName: result.item.name,
            locationPath: result.locationPath,
            currentStock: result.item.quantity,
            requiredQuantity: 1,
          ),
        );
        _errorMessage = null;
      });
    }
  }

  Future<void> _addTextItem() async {
    final textController = TextEditingController();
    final quantityController = TextEditingController(text: '1');
    final dialogFormKey = GlobalKey<FormState>();

    final added = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加普通文本条目'),
        content: Form(
          key: dialogFormKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: textController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '条目内容 *',
                  hintText: '如：关好门窗、倒垃圾',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return '条目内容不能为空';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '所需数量 *',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  final n = int.tryParse(val ?? '');
                  if (n == null || n < 1) {
                    return '数量必须为正整数';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (dialogFormKey.currentState!.validate()) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );

    if (added == true && mounted) {
      final name = textController.text.trim();
      final quantity = int.parse(quantityController.text.trim());
      setState(() {
        _draftEntries.add(
          _SessionEntryDraft(
            id: null,
            itemType: textSessionItemType,
            textName: name,
            displayName: name,
            requiredQuantity: quantity,
          ),
        );
        _errorMessage = null;
      });
    }
  }

  Future<void> _editQuantity(int index) async {
    final entry = _draftEntries[index];
    final controller = TextEditingController(
      text: entry.requiredQuantity.toString(),
    );
    final dialogFormKey = GlobalKey<FormState>();

    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('修改“${entry.displayName}”所需数量'),
        content: Form(
          key: dialogFormKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: '所需数量 *',
              helperText: entry.currentStock != null
                  ? '当前物品库库存: ${entry.currentStock} 件'
                  : null,
              border: const OutlineInputBorder(),
            ),
            validator: (val) {
              final n = int.tryParse(val ?? '');
              if (n == null || n < 1) {
                return '数量必须为正整数';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (dialogFormKey.currentState!.validate()) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (updated == true && mounted) {
      setState(() {
        entry.requiredQuantity = int.parse(controller.text.trim());
      });
    }
  }

  Future<void> _editTextName(int index) async {
    final entry = _draftEntries[index];
    if (entry.isRegisteredItem) return;

    final controller = TextEditingController(text: entry.displayName);
    final dialogFormKey = GlobalKey<FormState>();

    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改普通文本条目内容'),
        content: Form(
          key: dialogFormKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '条目内容 *',
              border: OutlineInputBorder(),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return '条目内容不能为空';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (dialogFormKey.currentState!.validate()) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (updated == true && mounted) {
      setState(() {
        final name = controller.text.trim();
        entry.textName = name;
        entry.displayName = name;
      });
    }
  }

  void _removeEntry(int index) {
    if (_draftEntries.length <= 1) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('出门任务至少需要保留一个条目，不能全部删除')));
      return;
    }
    setState(() {
      _draftEntries.removeAt(index);
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;

    if (_draftEntries.isEmpty) {
      setState(() {
        _errorMessage = '出门任务至少需要添加一个条目';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final title = _titleController.text.trim();
    final repo = ref.read(sessionRepositoryProvider);

    try {
      if (widget.isEditing) {
        final editableInputs = _draftEntries.map((e) {
          return EditableSessionEntryInput.raw(
            id: e.id,
            itemType: e.itemType,
            itemId: e.itemId,
            textName: e.textName,
            requiredQuantity: e.requiredQuantity,
          );
        }).toList();

        await repo.saveActiveSession(
          sessionId: widget.sessionId!,
          title: title,
          entries: editableInputs,
        );

        ref.read(sessionRefreshProvider.notifier).refresh();
        ref.invalidate(activeSessionsProvider);

        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('已保存出门任务“$title”的修改')));
        context.pop();
      } else {
        final inputs = _draftEntries.map((e) {
          if (e.isRegisteredItem) {
            return SessionEntryInput.registered(
              itemId: e.itemId!,
              requiredQuantity: e.requiredQuantity,
            );
          } else {
            return SessionEntryInput.text(
              textName: e.textName!,
              requiredQuantity: e.requiredQuantity,
            );
          }
        }).toList();

        final newSessionId = await repo.createDirect(
          title: title,
          entries: inputs,
        );

        ref.read(sessionRefreshProvider.notifier).refresh();
        ref.invalidate(activeSessionsProvider);

        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('已成功创建出门任务“$title”')));
        context.pushReplacement('/outings/sessions/$newSessionId');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e is SessionRepositoryException
              ? e.message
              : (widget.isEditing ? '保存修改失败，请重试' : '创建出门任务失败，请重试');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.isEditing ? '编辑出门任务' : '新建出门任务')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? '编辑出门任务' : '新建出门任务'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
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
                  : const Text('保存'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: '本次出门名称 *',
                        hintText: '如：日常通勤、临时下楼买菜',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '出门任务名称不能为空';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          '清单条目 (${_draftEntries.length})',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '长按右侧把手可拖拽排序',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                    if (_draftEntries.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 36),
                        alignment: Alignment.center,
                        child: Text(
                          '暂无条目，请点击下方按钮添加登记物品或普通文本',
                          style: TextStyle(color: theme.colorScheme.outline),
                        ),
                      )
                    else
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _draftEntries.length,
                        onReorderItem: (oldIndex, newIndex) {
                          setState(() {
                            final item = _draftEntries.removeAt(oldIndex);
                            _draftEntries.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final entry = _draftEntries[index];
                          return Card(
                            key: ValueKey(
                              'draft-entry-$index-${entry.displayName}',
                            ),
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
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
                                          color: entry.isRegisteredItem
                                              ? theme
                                                    .colorScheme
                                                    .primaryContainer
                                              : theme
                                                    .colorScheme
                                                    .secondaryContainer,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          entry.isRegisteredItem
                                              ? '登记物品'
                                              : '普通文本',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: entry.isRegisteredItem
                                                ? theme
                                                      .colorScheme
                                                      .onPrimaryContainer
                                                : theme
                                                      .colorScheme
                                                      .onSecondaryContainer,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: InkWell(
                                          onTap: entry.isRegisteredItem
                                              ? null
                                              : () => _editTextName(index),
                                          child: Text(
                                            entry.displayName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () => _editQuantity(index),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme
                                                .colorScheme
                                                .surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '需带: ${entry.requiredQuantity}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(width: 2),
                                              const Icon(Icons.edit, size: 12),
                                            ],
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 20,
                                        ),
                                        tooltip: '删除条目',
                                        onPressed: () => _removeEntry(index),
                                      ),
                                      ReorderableDragStartListener(
                                        index: index,
                                        child: const Icon(
                                          Icons.drag_handle,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (entry.isRegisteredItem &&
                                      entry.locationPath != null) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.place_outlined,
                                          size: 12,
                                          color: theme.colorScheme.outline,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          entry.locationPath!,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: theme.colorScheme.outline,
                                          ),
                                        ),
                                        if (entry.currentStock != null) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            '库存: ${entry.currentStock} 件',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: theme.colorScheme.outline,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                  if (entry.isShortage) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.errorContainer
                                            .withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '库存 ${entry.currentStock}，需带 ${entry.requiredQuantity}，缺少 ${entry.requiredQuantity - entry.currentStock!}（提醒：不影响保存）',
                                        style: TextStyle(
                                          color: theme.colorScheme.error,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.inventory_2_outlined),
                            label: const Text('添加登记物品'),
                            onPressed: _addRegisteredItem,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.text_fields),
                            label: const Text('添加普通文本'),
                            onPressed: _addTextItem,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

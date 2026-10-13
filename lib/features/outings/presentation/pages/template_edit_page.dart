import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../data/repositories/template_repository.dart';
import '../../application/template_providers.dart';
import '../widgets/template_item_picker_dialog.dart';

class TemplateDraftItem {
  TemplateDraftItem.registered({
    required this.itemId,
    required this.name,
    required this.locationPath,
    required this.currentQuantity,
    this.requiredQuantity = 1,
  }) : key = UniqueKey().toString(),
       itemType = registeredTemplateItemType,
       textName = null;

  TemplateDraftItem.text({required String textName, this.requiredQuantity = 1})
    : key = UniqueKey().toString(),
      itemType = textTemplateItemType,
      itemId = null,
      name = textName,
      textName = textName,
      locationPath = null,
      currentQuantity = null;

  final String key;
  final String itemType;
  final int? itemId;
  String name;
  final String? locationPath;
  final int? currentQuantity;
  int requiredQuantity;
  String? textName;

  bool get isRegistered => itemType == registeredTemplateItemType;

  int? get shortage {
    if (!isRegistered || currentQuantity == null) return null;
    final diff = requiredQuantity - currentQuantity!;
    return diff > 0 ? diff : null;
  }
}

class TemplateEditPage extends ConsumerStatefulWidget {
  const TemplateEditPage({this.templateId, super.key});

  final int? templateId;

  bool get isEditing => templateId != null;

  @override
  ConsumerState<TemplateEditPage> createState() => _TemplateEditPageState();
}

class _TemplateEditPageState extends ConsumerState<TemplateEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();

  final List<TemplateDraftItem> _draftItems = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    final id = widget.templateId;
    if (id != null) {
      try {
        final repo = ref.read(templateRepositoryProvider);
        final detail = await repo.getDetail(id);
        if (!mounted) return;
        _nameController.text = detail.template.name;
        _descController.text = detail.template.description ?? '';
        for (final entry in detail.entries) {
          if (entry.isRegisteredItem && entry.registeredItem != null) {
            _draftItems.add(
              TemplateDraftItem.registered(
                itemId: entry.entry.itemId!,
                name: entry.registeredItem!.name,
                locationPath: entry.locationPath ?? '未知位置',
                currentQuantity: entry.registeredItem!.quantity,
                requiredQuantity: entry.entry.requiredQuantity,
              ),
            );
          } else {
            _draftItems.add(
              TemplateDraftItem.text(
                textName: entry.displayName,
                requiredQuantity: entry.entry.requiredQuantity,
              ),
            );
          }
        }
      } catch (e) {
        if (!mounted) return;
        _errorMessage = e is TemplateRepositoryException ? e.message : '加载模板失败';
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Set<int> get _existingItemIds =>
      _draftItems.where((e) => e.itemId != null).map((e) => e.itemId!).toSet();

  Future<void> _addRegisteredItem() async {
    final result = await TemplateItemPickerDialog.show(
      context,
      excludedItemIds: _existingItemIds,
    );
    if (result != null && mounted) {
      setState(() {
        _draftItems.add(
          TemplateDraftItem.registered(
            itemId: result.item.id,
            name: result.item.name,
            locationPath: result.locationPath,
            currentQuantity: result.item.quantity,
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
    final dialogKey = GlobalKey<FormState>();

    final added = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加普通文本条目'),
        content: Form(
          key: dialogKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: textController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '条目内容 *',
                  hintText: '例如：带雨伞、倒垃圾、关电源',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return '内容不能为空';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: quantityController,
                decoration: const InputDecoration(
                  labelText: '需带数量 *',
                  hintText: '正整数',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (val) {
                  final parsed = int.tryParse(val?.trim() ?? '');
                  if (parsed == null || parsed < 1) {
                    return '数量必须大于等于 1';
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
              if (dialogKey.currentState!.validate()) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );

    if (added == true && mounted) {
      setState(() {
        _draftItems.add(
          TemplateDraftItem.text(
            textName: textController.text.trim(),
            requiredQuantity: int.parse(quantityController.text.trim()),
          ),
        );
        _errorMessage = null;
      });
    }
  }

  Future<void> _editQuantity(TemplateDraftItem item) async {
    final controller = TextEditingController(
      text: item.requiredQuantity.toString(),
    );
    final key = GlobalKey<FormState>();

    final updated = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('修改“${item.name}”的所需数量'),
        content: Form(
          key: key,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '所需数量 *',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            validator: (val) {
              final parsed = int.tryParse(val?.trim() ?? '');
              if (parsed == null || parsed < 1) {
                return '数量必须大于等于 1';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) {
                Navigator.of(context).pop(int.parse(controller.text.trim()));
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (updated != null && mounted) {
      setState(() {
        item.requiredQuantity = updated;
      });
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;

    if (_draftItems.isEmpty) {
      setState(() {
        _errorMessage = '模板至少需要添加一个条目';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final name = _nameController.text.trim();
    final desc = _descController.text.trim().isEmpty
        ? null
        : _descController.text.trim();

    final entries = <TemplateEntryInput>[];
    for (var i = 0; i < _draftItems.length; i++) {
      final item = _draftItems[i];
      if (item.isRegistered) {
        entries.add(
          TemplateEntryInput.registered(
            itemId: item.itemId!,
            requiredQuantity: item.requiredQuantity,
            sortOrder: i,
          ),
        );
      } else {
        entries.add(
          TemplateEntryInput.text(
            textName: item.textName ?? item.name,
            requiredQuantity: item.requiredQuantity,
            sortOrder: i,
          ),
        );
      }
    }

    try {
      final repo = ref.read(templateRepositoryProvider);
      if (widget.isEditing) {
        await repo.updateTemplate(
          id: widget.templateId!,
          name: name,
          description: Value(desc),
        );
        await repo.replaceEntries(
          templateId: widget.templateId!,
          entries: entries,
        );
      } else {
        await repo.create(name: name, description: desc, entries: entries);
      }

      ref.read(templateRefreshProvider.notifier).refresh();

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(widget.isEditing ? '已保存模板“$name”' : '已成功创建模板“$name”'),
          ),
        );
      context.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e is TemplateRepositoryException
              ? e.message
              : '保存失败，请重试';
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.isEditing ? '编辑模板' : '新建出门模板')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? '编辑模板' : '新建出门模板'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
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
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: MaterialBanner(
                          backgroundColor: theme.colorScheme.errorContainer,
                          content: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  setState(() => _errorMessage = null),
                              child: const Text('关闭'),
                            ),
                          ],
                        ),
                      ),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: '模板名称 *',
                        hintText: '例如：日常通勤、雨天出门、周末短途',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.description_outlined),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return '模板名称不能为空';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descController,
                      decoration: const InputDecoration(
                        labelText: '模板描述（可选）',
                        hintText: '记录该模板的使用场景或备忘说明',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '条目清单（${_draftItems.length} 项）',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '长按可拖拽排序',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_draftItems.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 36),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.playlist_add,
                              size: 40,
                              color: theme.colorScheme.outline,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '暂未添加任何条目\n请点击下方按钮添加登记物品或文本',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _draftItems.length,
                        onReorderItem: (oldIndex, newIndex) {
                          setState(() {
                            final item = _draftItems.removeAt(oldIndex);
                            _draftItems.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final item = _draftItems[index];
                          return Card(
                            key: ValueKey(item.key),
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
                                      ReorderableDragStartListener(
                                        index: index,
                                        child: const Icon(
                                          Icons.drag_handle,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Chip(
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        labelStyle: const TextStyle(
                                          fontSize: 10,
                                        ),
                                        label: Text(
                                          item.isRegistered ? '已登记' : '普通文本',
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          item.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () => _editQuantity(item),
                                        borderRadius: BorderRadius.circular(6),
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
                                                '需带: ${item.requiredQuantity}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              const Icon(Icons.edit, size: 14),
                                            ],
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.red,
                                        ),
                                        tooltip: '删除条目',
                                        onPressed: () {
                                          setState(() {
                                            _draftItems.removeAt(index);
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                  if (item.isRegistered) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '位置：${item.locationPath ?? "未知"} | 当前库存：${item.currentQuantity ?? 0}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme.colorScheme.outline,
                                          ),
                                    ),
                                  ],
                                  if (item.shortage != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '⚠️ 库存 ${item.currentQuantity}，需带 ${item.requiredQuantity}，缺少 ${item.shortage}（提醒：不影响保存）',
                                      style: TextStyle(
                                        color: theme.colorScheme.error,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      offset: const Offset(0, -2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.add_shopping_cart),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

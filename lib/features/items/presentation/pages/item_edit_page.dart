import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../data/repositories/item_repository.dart';
import '../../application/location_providers.dart';
import '../widgets/item_location_picker.dart';

class ItemEditPage extends ConsumerStatefulWidget {
  const ItemEditPage({this.itemId, this.initialLocationId, super.key});

  final int? itemId;
  final int? initialLocationId;

  bool get isEditing => itemId != null;

  @override
  ConsumerState<ItemEditPage> createState() => _ItemEditPageState();
}

class _ItemEditPageState extends ConsumerState<ItemEditPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _categoryController = TextEditingController();
  final _noteController = TextEditingController();

  int? _selectedLocationId;
  String _selectedLocationPath = '未选择';
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _categoryController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    final itemId = widget.itemId;
    final itemRepo = ref.read(itemRepositoryProvider);
    final locationRepo = ref.read(locationRepositoryProvider);

    if (itemId != null) {
      try {
        final item = await itemRepo.getById(itemId);
        final path = await itemRepo.fullLocationPath(itemId);
        if (!mounted) return;
        _nameController.text = item.name;
        _quantityController.text = item.quantity.toString();
        _categoryController.text = item.category ?? '';
        _noteController.text = item.note ?? '';
        _selectedLocationId = item.locationId;
        _selectedLocationPath = path;
      } catch (e) {
        if (!mounted) return;
        _errorMessage = e is ItemRepositoryException ? e.message : '加载物品信息失败';
      }
    } else if (widget.initialLocationId != null) {
      try {
        final locId = widget.initialLocationId!;
        final path = await locationRepo.fullPath(locId);
        if (!mounted) return;
        _selectedLocationId = locId;
        _selectedLocationPath = path;
      } catch (_) {
        // Fallback to unselected
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickLocation() async {
    final selected = await ItemLocationPicker.show(
      context,
      initialLocationId: _selectedLocationId,
    );
    if (selected != null && mounted) {
      final path = await ref
          .read(locationRepositoryProvider)
          .fullPath(selected.id);
      if (mounted) {
        setState(() {
          _selectedLocationId = selected.id;
          _selectedLocationPath = path;
          _errorMessage = null;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;

    if (_selectedLocationId == null) {
      setState(() {
        _errorMessage = '请选择物品所属的收纳位置';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final name = _nameController.text.trim();
    final quantity = int.parse(_quantityController.text.trim());
    final categoryText = _categoryController.text.trim();
    final noteText = _noteController.text.trim();
    final locationId = _selectedLocationId!;

    try {
      final itemRepo = ref.read(itemRepositoryProvider);
      if (widget.isEditing) {
        await itemRepo.update(
          id: widget.itemId!,
          name: name,
          quantity: quantity,
          locationId: locationId,
          category: Value(categoryText.isEmpty ? null : categoryText),
          note: Value(noteText.isEmpty ? null : noteText),
        );
      } else {
        await itemRepo.create(
          name: name,
          quantity: quantity,
          locationId: locationId,
          category: categoryText.isEmpty ? null : categoryText,
          note: noteText.isEmpty ? null : noteText,
        );
      }

      ref.read(locationBrowserRefreshProvider.notifier).refresh();

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              widget.isEditing ? '已保存物品“$name”的修改' : '已成功添加物品“$name”',
            ),
          ),
        );
      context.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e is ItemRepositoryException
              ? e.message
              : (widget.isEditing ? '保存修改失败，请重试' : '添加物品失败，请重试');
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.isEditing ? '编辑物品' : '添加物品')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? '编辑物品' : '添加物品'),
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
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: MaterialBanner(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .errorContainer,
                    content: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => setState(() => _errorMessage = null),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                ),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '物品名称 *',
                  hintText: '输入物品名称',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '物品名称不能为空';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _quantityController,
                decoration: const InputDecoration(
                  labelText: '存放数量 *',
                  hintText: '正整数',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.numbers_outlined),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '物品数量不能为空';
                  }
                  final parsed = int.tryParse(value.trim());
                  if (parsed == null || parsed < 1) {
                    return '物品数量必须是大于或等于 1 的正整数';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: _selectedLocationId == null
                        ? Theme.of(context).colorScheme.outline
                        : Theme.of(context).colorScheme.primary,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: const Text('所属收纳位置 *'),
                  subtitle: Text(
                    _selectedLocationPath,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _isSubmitting ? null : _pickLocation,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  labelText: '分类（可选）',
                  hintText: '例如：数码、药品、衣物',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: '备注（可选）',
                  hintText: '记录物品补充说明',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../data/local/app_database.dart';
import '../../../../data/repositories/location_repository.dart';
import '../../application/location_providers.dart';

class ItemsPage extends ConsumerStatefulWidget {
  const ItemsPage({super.key});

  @override
  ConsumerState<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends ConsumerState<ItemsPage> {
  int? _currentLocationId;
  final List<Location> _breadcrumbs = [];

  @override
  Widget build(BuildContext context) {
    final locations = ref.watch(locationChildrenProvider(_currentLocationId));

    return Scaffold(
      appBar: AppBar(title: const Text('物品')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                '收纳位置',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
            ),
            _buildBreadcrumbs(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshLocations,
                child: locations.when(
                  loading: () => ListView(
                    children: [
                      SizedBox(
                        height: 240,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                    ],
                  ),
                  error: (error, stackTrace) => _buildErrorState(error),
                  data: _buildLocationList,
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateLocationDialog,
        icon: const Icon(Icons.add),
        label: Text(_currentLocationId == null ? '新建位置' : '新建子位置'),
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            TextButton(
              onPressed: _currentLocationId == null
                  ? null
                  : () {
                      setState(() {
                        _currentLocationId = null;
                        _breadcrumbs.clear();
                      });
                    },
              child: const Text('我的收纳位置'),
            ),
            for (var index = 0; index < _breadcrumbs.length; index += 1) ...[
              const Text('/'),
              TextButton(
                onPressed: index == _breadcrumbs.length - 1
                    ? null
                    : () => _openBreadcrumb(index),
                child: Text(_breadcrumbs[index].name),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocationList(List<Location> locations) {
    if (locations.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 240,
            child: Center(
              child: Text(_currentLocationId == null ? '还没有收纳位置' : '当前没有子位置'),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: locations.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final location = locations[index];
        return ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(location.name),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openLocation(location),
        );
      },
    );
  }

  Widget _buildErrorState(Object error) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.error_outline, size: 40),
        const SizedBox(height: 12),
        Text(_friendlyError(error), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            onPressed: () {
              ref.invalidate(locationChildrenProvider(_currentLocationId));
            },
            icon: const Icon(Icons.refresh),
            label: const Text('重新加载'),
          ),
        ),
      ],
    );
  }

  void _openLocation(Location location) {
    setState(() {
      _currentLocationId = location.id;
      _breadcrumbs.add(location);
    });
  }

  void _openBreadcrumb(int index) {
    setState(() {
      _currentLocationId = _breadcrumbs[index].id;
      _breadcrumbs.removeRange(index + 1, _breadcrumbs.length);
    });
  }

  Future<void> _refreshLocations() async {
    final provider = locationChildrenProvider(_currentLocationId);
    ref.invalidate(provider);
    await ref.read(provider.future);
  }

  Future<void> _showCreateLocationDialog() async {
    final parentId = _currentLocationId;
    await showDialog<bool>(
      context: context,
      builder: (context) {
        return _CreateLocationDialog(
          title: parentId == null ? '新建顶层位置' : '新建子位置',
          onSubmit: (name) async {
            await ref
                .read(locationRepositoryProvider)
                .create(name: name, parentId: parentId);
            ref.invalidate(locationChildrenProvider(parentId));
          },
        );
      },
    );
  }

  String _friendlyError(Object error) {
    if (error is LocationRepositoryException) {
      return error.message;
    }
    return '读取收纳位置失败，请重试';
  }
}

class _CreateLocationDialog extends StatefulWidget {
  const _CreateLocationDialog({required this.title, required this.onSubmit});

  final String title;
  final Future<void> Function(String name) onSubmit;

  @override
  State<_CreateLocationDialog> createState() => _CreateLocationDialogState();
}

class _CreateLocationDialogState extends State<_CreateLocationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String? _errorMessage;
  bool _isSaving = false;

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
        child: TextFormField(
          controller: _nameController,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: '位置名称',
            errorText: _errorMessage,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return '位置名称不能为空';
            }
            return null;
          },
          onFieldSubmitted: _isSaving ? null : (_) => _submit(),
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
    } on LocationRepositoryException catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error.message;
          _isSaving = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = '保存收纳位置失败，请重试';
          _isSaving = false;
        });
      }
    }
  }
}

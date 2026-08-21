import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import '../../../application/favorites/chat_favorites_facade.dart';

/// 点击收藏按钮后弹出的选择/新建收藏夹对话框。
///
/// [collections] 由调用方提供且始终包含系统"未分类"收藏夹；
/// [initialCollectionId] 是调用方解析好的最近有效收藏夹（缺省系统夹），
/// 作为对话框预选项。新建收藏夹只被选中，用户再次确认才返回目标 ID；
/// 取消返回 null。
class AddToFavoritesDialog extends StatefulWidget {
  const AddToFavoritesDialog({
    required this.collections,
    required this.initialCollectionId,
    required this.onCreateCollection,
    super.key,
  });

  final List<ChatFavoriteCollectionOption> collections;

  /// 初始选中的收藏夹 ID：调用方传入的最近有效归类目标。
  final String initialCollectionId;

  /// 创建收藏夹回调；返回新夹 ID，null 表示创建失败。
  final String? Function(String name) onCreateCollection;

  @override
  State<AddToFavoritesDialog> createState() => _AddToFavoritesDialogState();
}

class _AddToFavoritesDialogState extends State<AddToFavoritesDialog> {
  late String _selectedCollectionId = widget.initialCollectionId;
  bool _showNewCollectionField = false;
  String? _errorMessage;
  late final TextEditingController _newNameController;

  @override
  void initState() {
    super.initState();
    _newNameController = TextEditingController();
  }

  @override
  void dispose() {
    _newNameController.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_errorMessage == null) return;
    setState(() => _errorMessage = null);
  }

  void _createAndSelect() {
    final name = _newNameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = '请输入收藏夹名称');
      return;
    }
    // 系统保留名在 UI 层拦截，避免依赖底层实现的归位语义。
    if (name == AppReservedEntities.uncategorizedFavoriteCollectionName) {
      setState(() => _errorMessage = '该名称被系统收藏夹保留');
      return;
    }

    final newId = widget.onCreateCollection(name);
    if (newId == null) {
      setState(() => _errorMessage = '创建失败，请稍后重试。');
      return;
    }

    // 创建后停留在对话框并选中新夹；收藏仍需用户再次确认。
    setState(() {
      _selectedCollectionId = newId;
      _showNewCollectionField = false;
      _errorMessage = null;
      _newNameController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final collections = widget.collections;

    return AlertDialog(
      title: const Text('收藏到'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // "未分类"来自真实系统收藏夹行，不再渲染手写 sentinel 选项。
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: collections.length,
                itemBuilder: (context, index) {
                  final collection = collections[index];
                  return _CollectionTile(
                    label: collection.name,
                    icon: collection.isSystem
                        ? Icons.folder_special_outlined
                        : Icons.folder_outlined,
                    selected: _selectedCollectionId == collection.id,
                    onTap: () {
                      _clearError();
                      setState(() => _selectedCollectionId = collection.id);
                    },
                  );
                },
              ),
            ),
            const Divider(height: 16),
            if (_showNewCollectionField)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _newNameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: '收藏夹名称',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    errorText: _errorMessage,
                  ),
                  onSubmitted: (_) => _createAndSelect(),
                ),
              )
            else
              TextButton.icon(
                onPressed: () => setState(() => _showNewCollectionField = true),
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('新建收藏夹'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        if (_showNewCollectionField)
          FilledButton(onPressed: _createAndSelect, child: const Text('创建'))
        else
          FilledButton(
            onPressed: _selectedCollectionId.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selectedCollectionId),
            child: const Text('收藏'),
          ),
      ],
    );
  }
}

/// 收藏夹选项行，支持选中高亮。
class _CollectionTile extends StatelessWidget {
  const _CollectionTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.secondaryContainer
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: selected
                        ? theme.colorScheme.onSecondaryContainer
                        : null,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

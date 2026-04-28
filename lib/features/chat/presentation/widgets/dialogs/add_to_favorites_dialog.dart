import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../favorites/application/collections_controller.dart';
import '../../../../favorites/domain/models/collection.dart';

/// 点击收藏按钮后弹出的选择/新建收藏夹对话框。
///
/// 返回用户选择的收藏夹 ID（'' 表示未分类）或 null（取消）。
class AddToFavoritesDialog extends ConsumerStatefulWidget {
  const AddToFavoritesDialog({
    required this.assistantContent,
    super.key,
  });

  /// 当前助手消息内容，用于判断是否已被收藏。
  final String assistantContent;

  @override
  ConsumerState<AddToFavoritesDialog> createState() =>
      _AddToFavoritesDialogState();
}

class _AddToFavoritesDialogState extends ConsumerState<AddToFavoritesDialog> {
  String? _selectedCollectionId;
  bool _showNewCollectionField = false;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final collections = ref.watch(collectionsProvider);

    return AlertDialog(
      title: const Text('收藏到'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 未分类选项
            _CollectionTile(
              label: '未分类',
              icon: Icons.folder_off_outlined,
              selected: _selectedCollectionId == '',
              onTap: () => setState(() => _selectedCollectionId = ''),
            ),
            if (collections.isNotEmpty) ...[
              const Divider(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: collections.length,
                  itemBuilder: (context, index) {
                    final collection = collections[index];
                    return _CollectionTile(
                      label: collection.name,
                      icon: Icons.folder_outlined,
                      selected: _selectedCollectionId == collection.id,
                      onTap: () =>
                          setState(() => _selectedCollectionId = collection.id),
                    );
                  },
                ),
              ),
            ],
            const Divider(height: 16),
            if (_showNewCollectionField)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _newNameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '收藏夹名称',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _createAndSelect(collections),
                ),
              )
            else
              TextButton.icon(
                onPressed: () =>
                    setState(() => _showNewCollectionField = true),
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
          FilledButton(
            onPressed: () => _createAndSelect(collections),
            child: const Text('新建并收藏'),
          )
        else
          FilledButton(
            onPressed: _selectedCollectionId != null
                ? () => Navigator.of(context).pop(_selectedCollectionId)
                : null,
            child: const Text('收藏'),
          ),
      ],
    );
  }

  void _createAndSelect(List<FavoriteCollection> existingCollections) {
    final name = _newNameController.text.trim();
    if (name.isEmpty) {
      return;
    }
    final newId = ref.read(collectionsProvider.notifier).create(name);
    Navigator.of(context).pop(newId);
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
      color: selected ? theme.colorScheme.secondaryContainer : Colors.transparent,
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
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
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

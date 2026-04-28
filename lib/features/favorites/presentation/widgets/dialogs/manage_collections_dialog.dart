import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/collections_controller.dart';
import '../../../domain/models/collection.dart';

/// 收藏夹管理对话框，支持查看、重命名和删除收藏夹。
class ManageCollectionsDialog extends ConsumerStatefulWidget {
  const ManageCollectionsDialog({super.key});

  @override
  ConsumerState<ManageCollectionsDialog> createState() =>
      _ManageCollectionsDialogState();
}

class _ManageCollectionsDialogState
    extends ConsumerState<ManageCollectionsDialog> {
  /// 当前正在编辑的收藏夹 ID，null 表示无编辑状态。
  String? _editingId;
  late final TextEditingController _renameController;

  @override
  void initState() {
    super.initState();
    _renameController = TextEditingController();
  }

  @override
  void dispose() {
    _renameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final collections = ref.watch(collectionsProvider);

    return AlertDialog(
      title: const Text('管理收藏夹'),
      content: SizedBox(
        width: double.maxFinite,
        child: collections.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  '暂无收藏夹。收藏回复时可创建。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: collections.length,
                  itemBuilder: (context, index) {
                    final collection = collections[index];
                    return _buildCollectionTile(context, theme, collection);
                  },
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildCollectionTile(
    BuildContext context,
    ThemeData theme,
    FavoriteCollection collection,
  ) {
    final isEditing = _editingId == collection.id;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: const Icon(Icons.folder_outlined),
      title: isEditing
          ? TextField(
              controller: _renameController,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _commitRename(collection.id),
            )
          : Text(collection.name),
      trailing: isEditing
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check_rounded),
                  tooltip: '确认重命名',
                  onPressed: () => _commitRename(collection.id),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: '取消',
                  onPressed: () => setState(() => _editingId = null),
                ),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: '重命名',
                  onPressed: () {
                    setState(() {
                      _editingId = collection.id;
                      _renameController.text = collection.name;
                    });
                  },
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: theme.colorScheme.error,
                  ),
                  tooltip: '删除收藏夹（内部收藏移入未分类）',
                  onPressed: () => _confirmDelete(context, collection),
                ),
              ],
            ),
    );
  }

  void _commitRename(String collectionId) {
    final name = _renameController.text.trim();
    if (name.isNotEmpty) {
      ref.read(collectionsProvider.notifier).rename(collectionId, name);
    }
    setState(() => _editingId = null);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    FavoriteCollection collection,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除收藏夹'),
          content: Text(
            '删除"${collection.name}"后，其中的收藏将移入未分类。确定删除吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      ref.read(collectionsProvider.notifier).delete(collection.id);
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import '../../../application/collections_controller.dart';
import '../../../application/favorites_clock_provider.dart';
import '../../../application/favorites_controller.dart';
import '../../../domain/models/collection_delete_request.dart';
import '../dialogs/edit_collection_dialog.dart';

/// 删除收藏夹对话框的去向选择模式。
enum _CollectionDeleteDisposition { move, deleteItems }

/// 非空收藏夹删除对话框：先决定夹内收藏去向，再最终确认删除。
///
/// 默认去向为移动到系统"未分类"；可选择其他普通收藏夹或在对话框内新建
/// 去向（新夹只被选中，仍需最终确认）。危险选项连同全部收藏一并删除。
/// 提交后事务完成前禁用确认按钮；失败时保持打开并内联报错。
class DeleteCollectionDialog extends ConsumerStatefulWidget {
  const DeleteCollectionDialog({
    required this.collectionId,
    required this.collectionName,
    required this.itemCount,
    super.key,
  });

  final String collectionId;
  final String collectionName;
  final int itemCount;

  @override
  ConsumerState<DeleteCollectionDialog> createState() =>
      _DeleteCollectionDialogState();
}

class _DeleteCollectionDialogState
    extends ConsumerState<DeleteCollectionDialog> {
  _CollectionDeleteDisposition _disposition = _CollectionDeleteDisposition.move;

  /// 移动去向；默认系统"未分类"，可为其他普通收藏夹或新建夹。
  String _moveTargetId = AppReservedEntities.uncategorizedFavoriteCollectionId;

  bool _isSubmitting = false;

  String? _errorMessage;

  FavoritesLibraryController get _library =>
      ref.read(favoritesLibraryProvider.notifier);

  Future<void> _createMoveTarget() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) =>
          const EditCollectionDialog(mode: EditCollectionDialogMode.create),
    );
    if (name == null || !mounted) return;

    final newId = _library.createCollection(name);
    // 新夹只被选中为去向；删除仍需用户再次确认。
    setState(() => _moveTargetId = newId);
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      _library.deleteCollection(
        widget.collectionId,
        disposition: switch (_disposition) {
          _CollectionDeleteDisposition.move =>
            CollectionDeleteRequest.moveItemsTo(
              targetCollectionId: _moveTargetId,
              assignedAt: ref.read(favoritesClockProvider)(),
            ),
          _CollectionDeleteDisposition.deleteItems =>
            CollectionDeleteRequest.deleteItems(),
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      // 事务失败：对话框保持打开，内联提示且不清空已选去向。
      setState(() {
        _isSubmitting = false;
        _errorMessage = '删除失败，请稍后重试。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(collectionsProvider);
    final theme = Theme.of(context);

    final moveTargets = collections
        .where((c) => c.id != widget.collectionId)
        .toList(growable: false);

    return AlertDialog(
      title: const Text('删除收藏夹'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${widget.collectionName}" 中有 ${widget.itemCount} 项收藏，'
              '请选择它们的去向。',
            ),
            const SizedBox(height: 8),
            // 处置方式组：移动到其他收藏夹，或连同收藏一并删除。
            RadioGroup<_CollectionDeleteDisposition>(
              groupValue: _disposition,
              onChanged: (value) => setState(() => _disposition = value!),
              child: Column(
                children: [
                  RadioListTile<_CollectionDeleteDisposition>(
                    value: _CollectionDeleteDisposition.move,
                    title: const Text('移入其他收藏夹'),
                  ),
                  RadioListTile<_CollectionDeleteDisposition>(
                    value: _CollectionDeleteDisposition.deleteItems,
                    title: Text(
                      '删除收藏夹及其中 ${widget.itemCount} 项收藏',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
            if (_disposition == _CollectionDeleteDisposition.move)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 移动去向组：不含待删除的收藏夹自身。
                    RadioGroup<String>(
                      groupValue: _moveTargetId,
                      onChanged: (value) =>
                          setState(() => _moveTargetId = value!),
                      child: Column(
                        children: [
                          for (final collection in moveTargets)
                            RadioListTile<String>(
                              value: collection.id,
                              title: Text(collection.name),
                              dense: true,
                            ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _createMoveTarget,
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 18,
                      ),
                      label: const Text('新建收藏夹作为去向'),
                    ),
                  ],
                ),
              ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _isSubmitting ? null : _submit,
          child: const Text('删除收藏夹'),
        ),
      ],
    );
  }
}

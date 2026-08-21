import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/collections_controller.dart';
import '../../../application/favorites_browse_preferences_controller.dart';
import '../../../application/favorites_controller.dart';
import 'edit_collection_dialog.dart';

/// 批量移动收藏到目标收藏夹的对话框。
///
/// 目标选项来自真实收藏夹列表（含系统"未分类"，不手写 sentinel 行）；
/// 初始选中最近归类目标，可在对话框内新建收藏夹（新夹仅被选中，移动仍需
/// 用户再次确认）。确认后把选中的收藏夹 ID pop 返回给调用方执行移动。
class MoveFavoritesDialog extends ConsumerStatefulWidget {
  const MoveFavoritesDialog({super.key});

  @override
  ConsumerState<MoveFavoritesDialog> createState() =>
      _MoveFavoritesDialogState();
}

class _MoveFavoritesDialogState extends ConsumerState<MoveFavoritesDialog> {
  String? _selectedCollectionId;

  @override
  void initState() {
    super.initState();
    // 初始选中最近归类目标；失效值由 provider 读取时回退系统"未分类"。
    _selectedCollectionId = ref.read(favoritesLastCollectionProvider);
  }

  Future<void> _createAndSelect() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) =>
          const EditCollectionDialog(mode: EditCollectionDialogMode.create),
    );
    if (name == null || !mounted) return;

    final newId = ref
        .read(favoritesLibraryProvider.notifier)
        .createCollection(name);
    // 新夹只被选中；移动仍需用户再次确认。
    setState(() => _selectedCollectionId = newId);
  }

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(collectionsProvider);

    return AlertDialog(
      title: const Text('移动到收藏夹'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: RadioGroup<String>(
                groupValue: _selectedCollectionId,
                onChanged: (value) =>
                    setState(() => _selectedCollectionId = value),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final collection in collections)
                      RadioListTile<String>(
                        value: collection.id,
                        title: Text(collection.name),
                        secondary: collection.isSystem
                            ? Icon(
                                Icons.folder_special_rounded,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : const Icon(Icons.folder_rounded),
                      ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _createAndSelect,
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: const Text('新建收藏夹'),
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
        FilledButton(
          onPressed: _selectedCollectionId == null
              ? null
              : () => Navigator.of(context).pop(_selectedCollectionId),
          child: const Text('移动'),
        ),
      ],
    );
  }
}

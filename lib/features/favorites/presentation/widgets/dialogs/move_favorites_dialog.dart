import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/collections_controller.dart';

/// 批量移动收藏到目标收藏夹的对话框。
///
/// 目标选项来自真实收藏夹列表（含系统"未分类"，不再手写 sentinel 行）；
/// 确认后把选中的收藏夹 ID pop 返回给调用方执行移动。
class MoveFavoritesDialog extends ConsumerStatefulWidget {
  const MoveFavoritesDialog({super.key});

  @override
  ConsumerState<MoveFavoritesDialog> createState() =>
      _MoveFavoritesDialogState();
}

class _MoveFavoritesDialogState extends ConsumerState<MoveFavoritesDialog> {
  String? _selectedCollectionId;

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(collectionsProvider);

    return AlertDialog(
      title: const Text('移动到收藏夹'),
      content: SizedBox(
        width: 320,
        child: RadioGroup<String>(
          groupValue: _selectedCollectionId,
          onChanged: (value) => setState(() => _selectedCollectionId = value),
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

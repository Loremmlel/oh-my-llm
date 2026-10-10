import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/widgets/app_dropdown_field.dart';

import '../../domain/models/collection.dart';

/// 收藏夹导航与批量选择共用一行，窄屏按实际可用宽度换行。
class FavoriteBrowseToolbar extends StatelessWidget {
  const FavoriteBrowseToolbar({
    required this.collections,
    required this.collectionId,
    required this.onCollectionChanged,
    required this.onSelect,
    required this.onManage,
    super.key,
  });

  final List<FavoriteCollection> collections;
  final String collectionId;
  final ValueChanged<String> onCollectionChanged;
  final VoidCallback? onSelect;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 216,
          child: AppDropdownField<String>(
            initialValue: collections.any((c) => c.id == collectionId)
                ? collectionId
                : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '收藏夹', isDense: true),
            items: [
              for (final c in collections)
                DropdownMenuItem(
                  value: c.id,
                  child: Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (id) {
              if (id != null && id != collectionId) onCollectionChanged(id);
            },
          ),
        ),
        OutlinedButton.icon(
          onPressed: onSelect,
          icon: const Icon(Icons.checklist),
          label: const Text('批量选择'),
        ),
        TextButton.icon(
          onPressed: onManage,
          icon: const Icon(Icons.folder_outlined),
          label: const Text('管理收藏夹'),
        ),
      ],
    ),
  );
}

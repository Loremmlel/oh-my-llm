import 'package:flutter/material.dart';

import '../../../settings/domain/models/preset_prompt.dart';

/// 预设 Prompt 消息的只读详情弹窗。
///
/// 展示消息标题、角色、位置和内容，不可编辑。内容区支持文本选中复制。
class PresetPromptMessageDetailDialog extends StatelessWidget {
  const PresetPromptMessageDetailDialog({
    required this.message,
    super.key,
  });

  final PromptMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(message.title, style: theme.textTheme.titleMedium),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.person_outline_rounded, size: 16),
                  label: Text(message.role.apiValue),
                  visualDensity: VisualDensity.compact,
                ),
                ActionChip(
                  avatar: const Icon(Icons.swap_vert_rounded, size: 16),
                  label: Text(message.placement.label),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(message.content),
          ],
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
}

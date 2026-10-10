import 'package:flutter/material.dart';

import '../../../../domain/models/prompts/memory_prompt.dart';
import '../../shared/settings_empty_state.dart';
import '../../shared/settings_entity_row.dart';
import '../../shared/settings_helpers.dart';

/// 记忆总结提示词列表。
class MemoryPromptsList extends StatelessWidget {
  const MemoryPromptsList({
    required this.memoryPrompts,
    required this.onEditRequested,
    required this.onDelete,
    super.key,
  });

  final List<MemoryPrompt> memoryPrompts;
  final ValueChanged<MemoryPrompt> onEditRequested;
  final Future<void> Function(String id) onDelete;

  @override
  Widget build(BuildContext context) {
    if (memoryPrompts.isEmpty) {
      return const SettingsEmptyState(
        icon: Icons.memory_rounded,
        title: '还没有记忆总结提示词',
        description: '添加后，聊天页创建检查点时就可以按不同场景选择不同的总结风格。',
      );
    }

    return Column(
      children: [
        for (final memoryPrompt in memoryPrompts)
          _MemoryPromptTile(
            memoryPrompt: memoryPrompt,
            onEditRequested: onEditRequested,
            onDelete: onDelete,
          ),
      ],
    );
  }
}

class _MemoryPromptTile extends StatelessWidget {
  const _MemoryPromptTile({
    required this.memoryPrompt,
    required this.onEditRequested,
    required this.onDelete,
  });

  final MemoryPrompt memoryPrompt;
  final ValueChanged<MemoryPrompt> onEditRequested;
  final Future<void> Function(String id) onDelete;

  @override
  Widget build(BuildContext context) {
    return SettingsEntityRow(
      title: memoryPrompt.name,
      body: [
        const SizedBox(height: 8),
        Text(
          memoryPrompt.summary,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ],
      actions: editDeleteActions(
        onEdit: () => onEditRequested(memoryPrompt),
        onDelete: () {
          onDelete(memoryPrompt.id).then((_) {
            if (context.mounted) {
              showSettingsSnackbar(context, '记忆总结提示词已删除');
            }
          });
        },
      ),
    );
  }
}

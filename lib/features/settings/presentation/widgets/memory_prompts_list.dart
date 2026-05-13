import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/memory_prompts_controller.dart';
import '../../domain/models/memory_prompt.dart';
import 'settings_card_grid.dart';
import 'settings_empty_state.dart';

/// 记忆总结提示词列表。
class MemoryPromptsList extends ConsumerWidget {
  const MemoryPromptsList({
    required this.memoryPrompts,
    required this.onEditRequested,
    super.key,
  });

  final List<MemoryPrompt> memoryPrompts;
  final ValueChanged<MemoryPrompt> onEditRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (memoryPrompts.isEmpty) {
      return const SettingsEmptyState(
        icon: Icons.memory_rounded,
        title: '还没有记忆总结提示词',
        description: '添加后，聊天页创建检查点时就可以按不同场景选择不同的总结风格。',
      );
    }

    return SettingsCardGrid(
      children: [
        for (final memoryPrompt in memoryPrompts)
          _MemoryPromptTile(
            memoryPrompt: memoryPrompt,
            onEditRequested: onEditRequested,
          ),
      ],
    );
  }
}

class _MemoryPromptTile extends ConsumerWidget {
  const _MemoryPromptTile({
    required this.memoryPrompt,
    required this.onEditRequested,
  });

  final MemoryPrompt memoryPrompt;
  final ValueChanged<MemoryPrompt> onEditRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(memoryPrompt.name, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              memoryPrompt.summary,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => onEditRequested(memoryPrompt),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref
                        .read(memoryPromptsProvider.notifier)
                        .deleteById(memoryPrompt.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('记忆总结提示词已删除')),
                      );
                    }
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

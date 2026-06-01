import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/application/preset_prompts_controller.dart';
import '../../../settings/domain/models/preset_prompt.dart';
import '../../domain/models/chat_conversation.dart';
import 'preset_prompt_message_card.dart';

/// 预设 Prompt 三级面板内容组件。
///
/// 顶部下拉选择预设，下方列出该预设内所有消息的开关卡片。
/// 宽屏三级栏和紧凑模式 endDrawer 共用此组件。
class PresetPromptPanel extends ConsumerWidget {
  const PresetPromptPanel({
    required this.selectedPresetPromptId,
    required this.onPresetPromptSelected,
    super.key,
  });

  /// 当前选中的预设 ID，null 表示"不使用预设"。
  final String? selectedPresetPromptId;

  /// 切换预设的回调。
  final ValueChanged<String?> onPresetPromptSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presetPrompts = ref.watch(presetPromptsProvider);
    final theme = Theme.of(context);

    final resolvedValue = selectedPresetPromptId ?? noPresetPromptSelectedId;

    // 查找当前选中的预设
    final selectedPreset = selectedPresetPromptId != null
        ? presetPrompts.where((p) => p.id == selectedPresetPromptId).firstOrNull
        : null;

    return Column(
      children: [
        // ── 预设选择器 ──────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: DropdownButtonFormField<String>(
            key: ValueKey(resolvedValue),
            initialValue: resolvedValue,
            decoration: const InputDecoration(
              labelText: '预设 Prompt',
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            isDense: true,
            isExpanded: true,
            items: [
              const DropdownMenuItem<String>(
                value: noPresetPromptSelectedId,
                child: Text('不使用预设 Prompt'),
              ),
              for (final preset in presetPrompts)
                DropdownMenuItem<String>(
                  value: preset.id,
                  child: Text(
                    preset.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              final mapped =
                  value == noPresetPromptSelectedId ? null : value;
              onPresetPromptSelected(mapped);
            },
          ),
        ),
        const Divider(height: 1),
        // ── 消息列表 / 空状态 ──────────────
        Expanded(
          child: _buildMessageList(theme, selectedPreset),
        ),
      ],
    );
  }

  Widget _buildMessageList(ThemeData theme, PresetPrompt? selectedPreset) {
    if (selectedPreset == null) {
      return Center(
        child: Text(
          '未选择预设',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (selectedPreset.messages.isEmpty) {
      return Center(
        child: Text(
          '此预设没有消息',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: selectedPreset.messages.length,
      itemBuilder: (context, index) {
        final message = selectedPreset.messages[index];
        return PresetPromptMessageCard(
          presetId: selectedPreset.id,
          message: message,
        );
      },
    );
  }
}

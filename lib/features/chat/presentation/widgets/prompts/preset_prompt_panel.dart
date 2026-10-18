import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/widgets/app_dropdown_field.dart';
import 'package:oh_my_llm/core/widgets/app_help_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/features/settings/application/prompts/preset_prompts_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';

import '../../../domain/models/chat_conversation.dart';
import 'preset_prompt_message_card.dart';
import 'world_book_selector.dart';

/// 聊天抽屉内的预设 Prompt 配置。
///
/// 顶部下拉选择预设，下方列出该预设内所有消息的开关卡片。
/// 宽窄屏共用此组件，选择与消息开关即时生效。
class PresetPromptPanel extends ConsumerStatefulWidget {
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
  ConsumerState<PresetPromptPanel> createState() => _PresetPromptPanelState();
}

class _PresetPromptPanelState extends ConsumerState<PresetPromptPanel> {
  bool _saving = false;
  String? _error;

  Future<void> _save(Future<void> Function() action) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = '预设设置保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedPresetPromptId = widget.selectedPresetPromptId;
    final presetPrompts = ref.watch(presetPromptsProvider);
    final theme = Theme.of(context);

    final resolvedValue = selectedPresetPromptId ?? noPresetPromptSelectedId;

    // 查找当前选中的预设
    final selectedPreset = selectedPresetPromptId != null
        ? presetPrompts.where((p) => p.id == selectedPresetPromptId).firstOrNull
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WorldBookSelector(),
        // ── 预设选择器 ──────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: AppDropdownField<String>(
            key: ValueKey(resolvedValue),
            initialValue: resolvedValue,
            fillWidth: true,
            decoration: const InputDecoration(labelText: '预设 Prompt'),
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
                  child: Text(preset.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              final mapped = value == noPresetPromptSelectedId ? null : value;
              widget.onPresetPromptSelected(mapped);
            },
          ),
        ),
        if (selectedPreset != null) ...[
          Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  title: const Text('单 System Prompt'),
                  value: selectedPreset.singleSystemPrompt,
                  onChanged: _saving
                      ? null
                      : (enabled) => _save(
                          () => ref
                              .read(presetPromptsProvider.notifier)
                              .setSingleSystemPrompt(
                                selectedPreset.id,
                                enabled!,
                              ),
                        ),
                ),
              ),
              const AppHelpButton(
                title: '单 System Prompt',
                message: '连续的前置 System 合为一条；其余 System 按 User 发送。',
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  title: const Text('头部随机字符'),
                  value: selectedPreset.randomHeader,
                  onChanged: _saving
                      ? null
                      : (enabled) => _save(
                          () => ref
                              .read(presetPromptsProvider.notifier)
                              .setRandomHeader(selectedPreset.id, enabled!),
                        ),
                ),
              ),
              const AppHelpButton(
                title: '头部随机字符',
                message: '每次发送时生成 10–50 个可打印 ASCII 字符，作为预设第 0 条前置 System 消息；参与单 System 等预设规则。同一次发送的自动重试沿用相同内容。开关随当前预设保存。',
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ),
        ],
        const Divider(height: 1),
        // ── 消息列表 / 空状态 ──────────────
        Expanded(child: _buildMessageList(theme, selectedPreset)),
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
      key: PageStorageKey('chat-drawer-preset-${selectedPreset.id}'),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/text_formatting.dart';
import '../../../application/chat_defaults_controller.dart';
import '../../../application/preset_prompts_controller.dart';
import '../../../domain/models/preset_prompt.dart';
import '../settings_card_grid.dart';
import '../settings_empty_state.dart';
import '../settings_entity_card.dart';
import '../settings_helpers.dart';

/// Prompt 模板列表，负责展示、编辑和删除模板。
class PresetPromptsList extends ConsumerWidget {
  const PresetPromptsList({
    required this.templates,
    required this.onDuplicateRequested,
    required this.onEditRequested,
    super.key,
  });

  final List<PresetPrompt> templates;
  final Future<void> Function(PresetPrompt template) onDuplicateRequested;
  final ValueChanged<PresetPrompt> onEditRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (templates.isEmpty) {
      return const SettingsEmptyState(
        icon: Icons.notes_rounded,
        title: '还没有预设 Prompt',
        description:
            '添加后，聊天页就可以把它们作为 system、前置或后置上下文插入到对话里。',
      );
    }

    return SettingsCardGrid(
      children: [
        for (final template in templates)
          _PresetPromptTile(
            template: template,
            onDuplicateRequested: onDuplicateRequested,
            onEditRequested: onEditRequested,
          ),
      ],
    );
  }
}

/// 单个 Prompt 模板卡片。
class _PresetPromptTile extends ConsumerWidget {
  const _PresetPromptTile({
    required this.template,
    required this.onDuplicateRequested,
    required this.onEditRequested,
  });

  final PresetPrompt template;
  final Future<void> Function(PresetPrompt template) onDuplicateRequested;
  final ValueChanged<PresetPrompt> onEditRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return SettingsEntityCard(
      title: template.name,
      body: [
        const SizedBox(height: 8),
        Text(template.summary),
        if (template.messages.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final message in template.messages.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${_placementLabel(message.placement)} · ${message.role.label} · ${message.title}：${summarizeText(message.content)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ] else ...[
          const SizedBox(height: 8),
          Text('当前模板还没有任何条目。', style: theme.textTheme.bodySmall),
        ],
      ],
      actions: [
        OutlinedButton.icon(
          onPressed: () async {
            await onDuplicateRequested(template);
          },
          icon: const Icon(Icons.content_copy_rounded),
          label: const Text('复制'),
        ),
        ...editDeleteActions(
          onEdit: () => onEditRequested(template),
          onDelete: () {
            ref
                .read(presetPromptsProvider.notifier)
                .deleteById(template.id)
                .then((_) {
                  ref
                      .read(chatDefaultsProvider.notifier)
                      .clearRememberedPresetPromptIdIfMatches(template.id)
                      .then((_) {
                        if (context.mounted) {
                          showSettingsSnackbar(context, '预设 Prompt 已删除');
                        }
                      });
                });
          },
        ),
      ],
    );
  }

  String _placementLabel(PromptMessagePlacement placement) {
    return switch (placement) {
      PromptMessagePlacement.before => '前置',
      PromptMessagePlacement.after => '后置',
    };
  }
}

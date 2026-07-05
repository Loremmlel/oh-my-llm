import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/text_formatting.dart';
import '../../../application/template_prompts_controller.dart';
import '../../../domain/models/template_prompt.dart';
import '../settings_card_grid.dart';
import '../settings_empty_state.dart';
import '../settings_entity_card.dart';
import '../settings_helpers.dart';

/// 模板提示词列表，负责展示、编辑和删除模板。
class TemplatePromptsList extends ConsumerWidget {
  const TemplatePromptsList({
    required this.templatePrompts,
    required this.onEditRequested,
    super.key,
  });

  final List<TemplatePrompt> templatePrompts;
  final ValueChanged<TemplatePrompt> onEditRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (templatePrompts.isEmpty) {
      return const SettingsEmptyState(
        icon: Icons.dynamic_form_outlined,
        title: '还没有模板提示词',
        description: '添加后，聊天页就可以临时选择模板，并把正文与变量值注入进去。',
      );
    }

    return SettingsCardGrid(
      children: [
        for (final templatePrompt in templatePrompts)
          _TemplatePromptTile(
            templatePrompt: templatePrompt,
            onEditRequested: onEditRequested,
          ),
      ],
    );
  }
}

/// 单个模板提示词卡片。
class _TemplatePromptTile extends ConsumerWidget {
  const _TemplatePromptTile({
    required this.templatePrompt,
    required this.onEditRequested,
  });

  final TemplatePrompt templatePrompt;
  final ValueChanged<TemplatePrompt> onEditRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsEntityCard(
      title: templatePrompt.title,
      body: [
        const SizedBox(height: 8),
        Text(templatePrompt.summary),
        const SizedBox(height: 4),
        Text(
          summarizeText(templatePrompt.content, maxLength: 36),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (templatePrompt.variables.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '变量：${templatePrompt.variables.map((v) => v.name).join('、')}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
      actions: editDeleteActions(
        onEdit: () => onEditRequested(templatePrompt),
        onDelete: () {
          ref
              .read(templatePromptsProvider.notifier)
              .deleteById(templatePrompt.id)
              .then((_) {
                if (context.mounted) {
                  showSettingsSnackbar(context, '模板提示词已删除');
                }
              });
        },
      ),
    );
  }
}

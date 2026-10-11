import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/utils/text_formatting.dart';

import '../../../../domain/models/prompts/template_prompt.dart';
import '../../shared/settings_empty_state.dart';
import '../../shared/settings_entity_row.dart';
import '../../shared/settings_helpers.dart';

/// 模板提示词列表，负责展示、编辑和删除模板。
class TemplatePromptsList extends StatelessWidget {
  const TemplatePromptsList({
    required this.templatePrompts,
    required this.onEditRequested,
    required this.onDelete,
    super.key,
  });

  final List<TemplatePrompt> templatePrompts;
  final ValueChanged<TemplatePrompt> onEditRequested;
  final Future<void> Function(String id) onDelete;

  @override
  Widget build(BuildContext context) {
    if (templatePrompts.isEmpty) {
      return const SettingsEmptyState(
        icon: Icons.dynamic_form_outlined,
        title: '还没有模板提示词',
        description: '添加后，聊天页就可以临时选择模板，并把正文与变量值注入进去。',
      );
    }

    return Column(
      children: [
        for (final templatePrompt in templatePrompts)
          _TemplatePromptTile(
            templatePrompt: templatePrompt,
            onEditRequested: onEditRequested,
            onDelete: onDelete,
          ),
      ],
    );
  }
}

/// 单个模板提示词记录。
class _TemplatePromptTile extends StatelessWidget {
  const _TemplatePromptTile({
    required this.templatePrompt,
    required this.onEditRequested,
    required this.onDelete,
  });

  final TemplatePrompt templatePrompt;
  final ValueChanged<TemplatePrompt> onEditRequested;
  final Future<void> Function(String id) onDelete;

  @override
  Widget build(BuildContext context) {
    return SettingsEntityRow(
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
          onDelete(templatePrompt.id).then((_) {
            if (context.mounted) {
              showSettingsSnackbar(context, '模板提示词已删除');
            }
          });
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/template_prompts_controller.dart';
import '../../domain/models/template_prompt.dart';
import 'settings_card_grid.dart';
import 'settings_empty_state.dart';

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
  /// 构建模板列表；空列表时显示空状态提示。宽度足够时一行展示多列。
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
  /// 构建模板摘要、变量预览和操作按钮。
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
            Text(templatePrompt.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(templatePrompt.summary),
            const SizedBox(height: 4),
            Text(
              _summarize(templatePrompt.content),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (templatePrompt.variables.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '变量：${templatePrompt.variables.map((variable) => variable.name).join('、')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => onEditRequested(templatePrompt),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref
                        .read(templatePromptsProvider.notifier)
                        .deleteById(templatePrompt.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('模板提示词已删除')),
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

  String _summarize(String content) {
    final normalized = content.trim().replaceAll('\n', ' ');
    if (normalized.length <= 36) {
      return normalized;
    }
    return '${normalized.substring(0, 36)}...';
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/chat_defaults_controller.dart';
import '../../application/prompt_templates_controller.dart';
import '../../domain/models/prompt_template.dart';
import 'settings_empty_state.dart';

class PromptTemplatesList extends ConsumerWidget {
  const PromptTemplatesList({
    required this.templates,
    required this.onEditRequested,
    super.key,
  });

  final List<PromptTemplate> templates;
  final ValueChanged<PromptTemplate> onEditRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (templates.isEmpty) {
      return const SettingsEmptyState(
        icon: Icons.notes_rounded,
        title: '还没有 Prompt 模板',
        description: '添加模板后，聊天页就可以把它们作为 system / few-shot 上下文插入到对话最前面。',
      );
    }

    return Column(
      children: [
        for (final template in templates)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PromptTemplateTile(
              template: template,
              onEditRequested: onEditRequested,
            ),
          ),
      ],
    );
  }
}

class _PromptTemplateTile extends ConsumerWidget {
  const _PromptTemplateTile({
    required this.template,
    required this.onEditRequested,
  });

  final PromptTemplate template;
  final ValueChanged<PromptTemplate> onEditRequested;

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
            Text(template.name, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(template.summary),
            const SizedBox(height: 4),
            Text(
              'System：${_summarize(template.systemPrompt)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (template.messages.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final message in template.messages.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${message.role.label}：${_summarize(message.content)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => onEditRequested(template),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref
                        .read(promptTemplatesProvider.notifier)
                        .deleteById(template.id);
                    await ref
                        .read(chatDefaultsProvider.notifier)
                        .clearDefaultPromptTemplateIdIfMatches(template.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Prompt 模板已删除')),
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
    if (normalized.length <= 30) {
      return normalized;
    }

    return '${normalized.substring(0, 30)}...';
  }
}

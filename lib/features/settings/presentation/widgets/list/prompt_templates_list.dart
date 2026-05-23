import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/chat_defaults_controller.dart';
import '../../../application/prompt_templates_controller.dart';
import '../../../domain/models/prompt_template.dart';
import '../settings_card_grid.dart';
import '../settings_empty_state.dart';

/// Prompt 模板列表，负责展示、编辑和删除模板。
class PromptTemplatesList extends ConsumerWidget {
  const PromptTemplatesList({
    required this.templates,
    required this.onDuplicateRequested,
    required this.onEditRequested,
    super.key,
  });

  final List<PromptTemplate> templates;
  final Future<void> Function(PromptTemplate template) onDuplicateRequested;
  final ValueChanged<PromptTemplate> onEditRequested;

  @override
  /// 构建模板列表；空列表时显示空状态提示。宽度足够时一行展示多列。
  Widget build(BuildContext context, WidgetRef ref) {
    if (templates.isEmpty) {
      return const SettingsEmptyState(
        icon: Icons.notes_rounded,
        title: '还没有预设 Prompt',
        description: '添加后，聊天页就可以把它们作为 system、前置或后置上下文插入到对话里。',
      );
    }

    return SettingsCardGrid(
      children: [
        for (final template in templates)
          _PromptTemplateTile(
            template: template,
            onDuplicateRequested: onDuplicateRequested,
            onEditRequested: onEditRequested,
          ),
      ],
    );
  }
}

/// 单个 Prompt 模板卡片。
class _PromptTemplateTile extends ConsumerWidget {
  const _PromptTemplateTile({
    required this.template,
    required this.onDuplicateRequested,
    required this.onEditRequested,
  });

  final PromptTemplate template;
  final Future<void> Function(PromptTemplate template) onDuplicateRequested;
  final ValueChanged<PromptTemplate> onEditRequested;

  @override
  /// 构建模板摘要、附加消息预览和操作按钮。
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
            if (template.messages.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final message in template.messages.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${_placementLabel(message.placement)} · ${message.role.label} · ${message.title}：${_summarize(message.content)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ] else ...[
              const SizedBox(height: 8),
              Text('当前模板还没有任何条目。', style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    await onDuplicateRequested(template);
                  },
                  icon: const Icon(Icons.content_copy_rounded),
                  label: const Text('复制'),
                ),
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
                        .clearRememberedPromptTemplateIdIfMatches(template.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('预设 Prompt 已删除')),
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

  /// 把长文本截断为适合列表显示的摘要。
  String _summarize(String content) {
    final normalized = content.trim().replaceAll('\n', ' ');
    if (normalized.length <= 30) {
      return normalized;
    }

    return '${normalized.substring(0, 30)}...';
  }

  String _placementLabel(PromptMessagePlacement placement) {
    return switch (placement) {
      PromptMessagePlacement.before => '前置',
      PromptMessagePlacement.after => '后置',
    };
  }
}

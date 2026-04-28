import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/chat_defaults_controller.dart';
import '../../application/prompt_templates_controller.dart';
import '../../domain/models/prompt_template.dart';
import 'settings_empty_state.dart';

/// Prompt 模板列表，负责展示、编辑和删除模板。
class PromptTemplatesList extends ConsumerWidget {
  const PromptTemplatesList({
    required this.templates,
    required this.onEditRequested,
    super.key,
  });

  final List<PromptTemplate> templates;
  final ValueChanged<PromptTemplate> onEditRequested;

  @override
  /// 构建模板列表；空列表时显示空状态提示。宽度足够时一行展示多列。
  Widget build(BuildContext context, WidgetRef ref) {
    if (templates.isEmpty) {
      return const SettingsEmptyState(
        icon: Icons.notes_rounded,
        title: '还没有 Prompt 模板',
        description: '添加模板后，聊天页就可以把它们作为 system / few-shot 上下文插入到对话最前面。',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const minItemWidth = 280.0;
        const gap = 12.0;
        final crossAxisCount =
            ((constraints.maxWidth + gap) / (minItemWidth + gap))
                .floor()
                .clamp(1, 3);
        return _buildGrid(templates, crossAxisCount, gap, constraints.maxWidth, ref);
      },
    );
  }

  Widget _buildGrid(
    List<PromptTemplate> items,
    int crossAxisCount,
    double gap,
    double availableWidth,
    WidgetRef ref,
  ) {
    if (crossAxisCount == 1) {
      return Column(
        children: [
          for (final template in items)
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

    final itemWidth =
        (availableWidth - gap * (crossAxisCount - 1)) / crossAxisCount;
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += crossAxisCount) {
      final rowItems = items.skip(i).take(crossAxisCount).toList();
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var j = 0; j < rowItems.length; j++) ...[
                if (j > 0) SizedBox(width: gap),
                SizedBox(
                  width: itemWidth,
                  child: _PromptTemplateTile(
                    template: rowItems[j],
                    onEditRequested: onEditRequested,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

/// 单个 Prompt 模板卡片。
class _PromptTemplateTile extends ConsumerWidget {
  const _PromptTemplateTile({
    required this.template,
    required this.onEditRequested,
  });

  final PromptTemplate template;
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

  /// 把长文本截断为适合列表显示的摘要。
  String _summarize(String content) {
    final normalized = content.trim().replaceAll('\n', ' ');
    if (normalized.length <= 30) {
      return normalized;
    }

    return '${normalized.substring(0, 30)}...';
  }
}

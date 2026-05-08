import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/adaptive_master_detail_layout.dart';
import '../../application/chat_defaults_controller.dart';
import '../../application/prompt_templates_controller.dart';
import '../../domain/models/prompt_template.dart';
import 'settings_empty_state.dart';

/// Prompt 模板列表，负责展示、编辑和删除模板。
class PromptTemplatesList extends ConsumerStatefulWidget {
  const PromptTemplatesList({
    required this.templates,
    required this.onEditRequested,
    super.key,
  });

  final List<PromptTemplate> templates;
  final ValueChanged<PromptTemplate> onEditRequested;

  @override
  ConsumerState<PromptTemplatesList> createState() =>
      _PromptTemplatesListState();
}

class _PromptTemplatesListState extends ConsumerState<PromptTemplatesList> {
  String? _selectedTemplateId;

  @override
  void initState() {
    super.initState();
    _selectedTemplateId = widget.templates.isEmpty
        ? null
        : widget.templates.first.id;
  }

  @override
  void didUpdateWidget(covariant PromptTemplatesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.templates.isEmpty) {
      _selectedTemplateId = null;
      return;
    }
    final stillExists = widget.templates.any(
      (item) => item.id == _selectedTemplateId,
    );
    if (!stillExists) {
      _selectedTemplateId = widget.templates.first.id;
    }
  }

  PromptTemplate get _selectedTemplate {
    return widget.templates.firstWhere(
      (item) => item.id == _selectedTemplateId,
      orElse: () => widget.templates.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.templates.isEmpty) {
      return const SettingsEmptyState(
        icon: Icons.notes_rounded,
        title: '还没有 Prompt 模板',
        description: '添加模板后，聊天页就可以把它们作为 system / few-shot 上下文插入到对话最前面。',
      );
    }

    return AdaptiveMasterDetailLayout(
      key: const ValueKey('prompt-templates-master-detail'),
      breakpoint: 860,
      masterWidth: 300,
      minHeight: 420,
      compactChild: LayoutBuilder(
        builder: (context, constraints) {
          const minItemWidth = 280.0;
          const gap = 12.0;
          final crossAxisCount =
              ((constraints.maxWidth + gap) / (minItemWidth + gap))
                  .floor()
                  .clamp(1, 3);
          return _buildCompactGrid(
            widget.templates,
            crossAxisCount,
            gap,
            constraints.maxWidth,
          );
        },
      ),
      master: _PromptTemplateMasterPane(
        templates: widget.templates,
        selectedTemplateId: _selectedTemplate.id,
        onSelected: (template) {
          setState(() {
            _selectedTemplateId = template.id;
          });
        },
      ),
      detail: _PromptTemplateDetailPane(
        template: _selectedTemplate,
        onEditRequested: widget.onEditRequested,
      ),
    );
  }

  Widget _buildCompactGrid(
    List<PromptTemplate> items,
    int crossAxisCount,
    double gap,
    double availableWidth,
  ) {
    if (crossAxisCount == 1) {
      return Column(
        children: [
          for (final template in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PromptTemplateCompactTile(
                template: template,
                onEditRequested: widget.onEditRequested,
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
                  child: _PromptTemplateCompactTile(
                    template: rowItems[j],
                    onEditRequested: widget.onEditRequested,
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

class _PromptTemplateMasterPane extends StatelessWidget {
  const _PromptTemplateMasterPane({
    required this.templates,
    required this.selectedTemplateId,
    required this.onSelected,
  });

  final List<PromptTemplate> templates;
  final String selectedTemplateId;
  final ValueChanged<PromptTemplate> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.28,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ListView.separated(
          itemCount: templates.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final template = templates[index];
            return _PromptTemplateSelectionTile(
              template: template,
              selected: template.id == selectedTemplateId,
              onTap: () => onSelected(template),
            );
          },
        ),
      ),
    );
  }
}

class _PromptTemplateSelectionTile extends StatelessWidget {
  const _PromptTemplateSelectionTile({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final PromptTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.72)
          : colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(template.name, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                template.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                'System：${_summarizePromptTemplate(template.systemPrompt)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                template.messages.isEmpty
                    ? '仅 system 指令'
                    : '${template.messages.length} 条附加消息',
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromptTemplateDetailPane extends ConsumerWidget {
  const _PromptTemplateDetailPane({
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
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.18,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          template.name,
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          template.summary,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
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
                              .clearRememberedPromptTemplateIdIfMatches(
                                template.id,
                              );
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
              const SizedBox(height: 20),
              _PromptTemplateDetailBlock(
                title: 'System 指令',
                child: Text(
                  template.systemPrompt.trim().isEmpty
                      ? '未设置 system 指令。'
                      : template.systemPrompt,
                ),
              ),
              const SizedBox(height: 16),
              Text('附加消息', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (template.messages.isEmpty)
                Text('当前没有附加消息。', style: theme.textTheme.bodyMedium)
              else
                for (final message in template.messages) ...[
                  _PromptTemplateDetailBlock(
                    title:
                        '${message.role.label} · ${message.placement == PromptMessagePlacement.before ? '插入到会话前' : '插入到会话后'}',
                    child: Text(message.content),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PromptTemplateDetailBlock extends StatelessWidget {
  const _PromptTemplateDetailBlock({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

/// 窄屏下沿用摘要卡片布局。
class _PromptTemplateCompactTile extends ConsumerWidget {
  const _PromptTemplateCompactTile({
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
              'System：${_summarizePromptTemplate(template.systemPrompt)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (template.messages.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final message in template.messages.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${message.role.label}：${_summarizePromptTemplate(message.content)}',
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
                        .clearRememberedPromptTemplateIdIfMatches(template.id);
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
}

String _summarizePromptTemplate(String content) {
  final normalized = content.trim().replaceAll('\n', ' ');
  if (normalized.length <= 30) {
    return normalized;
  }

  return '${normalized.substring(0, 30)}...';
}

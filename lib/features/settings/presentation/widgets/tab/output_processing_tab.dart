import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/id_generator.dart';
import '../../../application/output_processing_settings_controller.dart';
import '../../../domain/models/output_processing_settings.dart';
import '../settings_helpers.dart';
import '../settings_section_card.dart';

/// 输出处理标签页：管理作用于模型回复正文的正则过滤/替换规则。
class OutputProcessingTab extends ConsumerWidget {
  const OutputProcessingTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(outputProcessingSettingsProvider);
    final controller = ref.read(outputProcessingSettingsProvider.notifier);
    final rules = [...settings.rules]
      ..sort((a, b) => a.order.compareTo(b.order));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SettingsSectionCard(
          title: '输出正则处理',
          description: '在模型回复正文落盘与展示前，按顺序应用正则规则做过滤或替换。'
              '替换字为空表示删除匹配内容。仅作用于正文，不影响推理过程；'
              '无效表达式会被静默跳过。',
          action: FilledButton.icon(
            onPressed: () => _openRuleDialog(context, controller, rules),
            icon: const Icon(Icons.add_rounded),
            label: const Text('新增规则'),
          ),
          child: rules.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '暂无正则规则，点击上方按钮添加',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < rules.length; i++)
                      _RuleTile(
                        index: i,
                        rule: rules[i],
                        onEdit: () => _openRuleDialog(
                          context,
                          controller,
                          rules,
                          editIndex: i,
                        ),
                        onToggle: (enabled) => _toggleRule(
                          controller,
                          rules,
                          i,
                          enabled,
                        ),
                        onMoveUp: i > 0
                            ? () => _moveRule(controller, rules, i, i - 1)
                            : null,
                        onMoveDown: i < rules.length - 1
                            ? () => _moveRule(controller, rules, i, i + 1)
                            : null,
                        onDelete: () =>
                            _confirmDelete(context, controller, rules, i),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _openRuleDialog(
    BuildContext context,
    OutputProcessingSettingsController controller,
    List<OutputRegexRule> rules, {
    int? editIndex,
  }) async {
    final existing = editIndex != null ? rules[editIndex] : null;
    final result = await showDialog<OutputRegexRule>(
      context: context,
      builder: (_) => _RuleFormDialog(initial: existing),
    );
    if (result == null) return;

    final next = [...rules];
    if (editIndex != null) {
      next[editIndex] = result.copyWith(order: rules[editIndex].order);
    } else {
      next.add(result.copyWith(order: rules.length));
    }
    await controller.save(
      OutputProcessingSettings(rules: _reindex(next)),
    );
    if (context.mounted) {
      showSettingsSnackbar(context, editIndex != null ? '规则已更新' : '规则已添加');
    }
  }

  Future<void> _toggleRule(
    OutputProcessingSettingsController controller,
    List<OutputRegexRule> rules,
    int index,
    bool enabled,
  ) async {
    final next = [...rules];
    next[index] = next[index].copyWith(enabled: enabled);
    await controller.save(OutputProcessingSettings(rules: _reindex(next)));
  }

  Future<void> _moveRule(
    OutputProcessingSettingsController controller,
    List<OutputRegexRule> rules,
    int from,
    int to,
  ) async {
    final next = [...rules];
    final moved = next.removeAt(from);
    next.insert(to, moved);
    await controller.save(OutputProcessingSettings(rules: _reindex(next)));
  }

  Future<void> _confirmDelete(
    BuildContext context,
    OutputProcessingSettingsController controller,
    List<OutputRegexRule> rules,
    int index,
  ) async {
    final title = rules[index].title.isEmpty ? '未命名规则' : rules[index].title;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('确认删除'),
          content: Text('确定要删除规则「$title」吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final next = [...rules]..removeAt(index);
      await controller.save(OutputProcessingSettings(rules: _reindex(next)));
      if (context.mounted) {
        showSettingsSnackbar(context, '规则已删除');
      }
    }
  }

  /// 按列表顺序重排 order，保证连续。
  List<OutputRegexRule> _reindex(List<OutputRegexRule> rules) {
    return [
      for (var i = 0; i < rules.length; i++) rules[i].copyWith(order: i),
    ];
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({
    required this.index,
    required this.rule,
    required this.onEdit,
    required this.onToggle,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  final int index;
  final OutputRegexRule rule;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final replacementLabel = rule.replacement.isEmpty
        ? '（删除匹配）'
        : '替换为：${rule.replacement}';

    return Padding(
      padding: EdgeInsets.only(top: index > 0 ? 8 : 0),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule.title.isEmpty ? '未命名规则' : rule.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rule.pattern,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamilyFallback: const ['monospace'],
                        color: theme.colorScheme.onSurface.withAlpha(179),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      replacementLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(140),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Switch(value: rule.enabled, onChanged: onToggle),
              IconButton(
                onPressed: onMoveUp,
                icon: const Icon(Icons.arrow_upward_rounded),
                tooltip: '上移',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: onMoveDown,
                icon: const Icon(Icons.arrow_downward_rounded),
                tooltip: '下移',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                tooltip: '编辑',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: onDelete,
                icon: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.error,
                ),
                tooltip: '删除',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleFormDialog extends StatefulWidget {
  const _RuleFormDialog({this.initial});

  final OutputRegexRule? initial;

  @override
  State<_RuleFormDialog> createState() => _RuleFormDialogState();
}

class _RuleFormDialogState extends State<_RuleFormDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _patternController;
  late final TextEditingController _replacementController;
  String? _patternError;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initial?.title ?? '');
    _patternController =
        TextEditingController(text: widget.initial?.pattern ?? '');
    _replacementController =
        TextEditingController(text: widget.initial?.replacement ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _patternController.dispose();
    _replacementController.dispose();
    super.dispose();
  }

  void _submit() {
    final pattern = _patternController.text;
    if (pattern.isEmpty) {
      setState(() => _patternError = '表达式不能为空');
      return;
    }
    try {
      RegExp(pattern, unicode: true);
    } on FormatException catch (error) {
      setState(() => _patternError = '无效正则：${error.message}');
      return;
    }

    Navigator.of(context).pop(
      OutputRegexRule(
        id: widget.initial?.id ?? generateEntityId(),
        title: _titleController.text.trim(),
        pattern: pattern,
        replacement: _replacementController.text,
        order: widget.initial?.order ?? 0,
        enabled: widget.initial?.enabled ?? true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '新增正则规则' : '编辑正则规则'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '标题',
                hintText: '例如：过滤「极其」增殖',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _patternController,
              decoration: InputDecoration(
                labelText: '正则表达式',
                hintText: r'例如：极其',
                errorText: _patternError,
              ),
              maxLines: 2,
              minLines: 1,
              onChanged: (_) {
                if (_patternError != null) {
                  setState(() => _patternError = null);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _replacementController,
              decoration: const InputDecoration(
                labelText: '替换字（留空表示删除匹配）',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

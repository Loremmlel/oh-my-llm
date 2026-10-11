import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/widgets/app_help_button.dart';

import '../../../../domain/models/prompts/preset_prompt.dart';
import '../../shared/settings_empty_state.dart';
import '../../shared/settings_table_row.dart';

const _columnFlexes = [4, 4, 2, 3, 5];
const _systemHelp = '连续的前置 System 合为一条；其余 System 按 User 发送。';

/// 列表只接收当前记录和命令，预览与真实页面使用同一布局。
class PresetPromptsView extends StatelessWidget {
  const PresetPromptsView({
    required this.templates,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
    required this.onSingleSystemChanged,
    super.key,
  });
  final List<PresetPrompt> templates;
  final Future<void> Function(PresetPrompt) onCopy;
  final ValueChanged<PresetPrompt> onEdit;
  final Future<void> Function(PresetPrompt) onDelete;
  final Future<void> Function(PresetPrompt, bool) onSingleSystemChanged;

  @override
  Widget build(BuildContext context) {
    if (templates.isEmpty) {
      return const SettingsEmptyState(
        icon: Icons.notes_rounded,
        title: '还没有预设 Prompt',
        description: '新增预设后即可在聊天中使用。',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
            AppBreakpoints.contentMasterDetail;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!compact)
              const SettingsTableRow(
                header: true,
                flexes: _columnFlexes,
                cells: [
                  Text('名称'),
                  Text('语法'),
                  Text('条目数量'),
                  AppHelpTitle(title: '单条 System', message: _systemHelp),
                  Text('操作'),
                ],
              ),
            for (final template in templates)
              PresetPromptRow(
                key: ValueKey(template.id),
                template: template,
                compact: compact,
                onCopy: () => onCopy(template),
                onEdit: () => onEdit(template),
                onDelete: () => onDelete(template),
                onSingleSystemChanged: (v) =>
                    onSingleSystemChanged(template, v),
              ),
          ],
        );
      },
    );
  }
}

class PresetPromptRow extends StatefulWidget {
  const PresetPromptRow({
    required this.template,
    required this.compact,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
    required this.onSingleSystemChanged,
    super.key,
  });
  final PresetPrompt template;
  final bool compact;
  final Future<void> Function() onCopy;
  final VoidCallback onEdit;
  final Future<void> Function() onDelete;
  final Future<void> Function(bool) onSingleSystemChanged;
  @override
  State<PresetPromptRow> createState() => _PresetPromptRowState();
}

class _PresetPromptRowState extends State<PresetPromptRow> {
  bool _pending = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    if (_pending) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = '操作失败，请重试');
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final template = widget.template;
    final theme = Theme.of(context);
    final syntax = template.syntax == PresetPromptSyntax.plain
        ? '普通文本'
        : 'SillyTavern 有限宏';
    final title = Tooltip(
      message: template.name,
      child: Text(
        template.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall,
      ),
    );
    final system = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: '单 System Prompt',
          child: Switch.adaptive(
            value: template.singleSystemPrompt,
            onChanged: _pending
                ? null
                : (v) => _run(() => widget.onSingleSystemChanged(v)),
          ),
        ),
        Flexible(
          child: Text(
            widget.compact
                ? '单条 System'
                : template.singleSystemPrompt
                ? '开启'
                : '关闭',
          ),
        ),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          onPressed: _pending ? null : widget.onEdit,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('编辑'),
        ),
        TextButton.icon(
          onPressed: _pending ? null : () => _run(widget.onCopy),
          icon: const Icon(Icons.content_copy_outlined, size: 18),
          label: const Text('复制'),
        ),
        PopupMenuButton<String>(
          tooltip: '预设操作',
          enabled: !_pending,
          onSelected: (_) => _run(widget.onDelete),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'delete',
              child: Text(
                '删除',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
        ),
      ],
    );
    final row = widget.compact
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$syntax · ${template.messages.length} 条',
                  style: theme.textTheme.bodySmall,
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(width: 170, child: system),
                    actions,
                  ],
                ),
                const Divider(height: 1),
              ],
            ),
          )
        : SettingsTableRow(
            flexes: _columnFlexes,
            cells: [
              title,
              Text(syntax),
              Text('${template.messages.length} 条'),
              system,
              actions,
            ],
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ),
      ],
    );
  }
}

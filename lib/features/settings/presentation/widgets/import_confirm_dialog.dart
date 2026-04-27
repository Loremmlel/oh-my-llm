import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/fixed_prompt_sequences_controller.dart';
import '../../application/llm_model_configs_controller.dart';
import '../../application/prompt_templates_controller.dart';
import '../../domain/models/settings_export_data.dart';

/// 配置导入确认对话框。
///
/// 当检测到剪贴板中含有本应用导出的配置数据（标识符匹配）时弹出，
/// 展示将要导入的各类条目数量，由用户决定是否继续导入。
class ImportConfirmDialog extends ConsumerStatefulWidget {
  const ImportConfirmDialog({required this.exportData, super.key});

  /// 已从剪贴板解析出的待导入数据。
  final SettingsExportData exportData;

  @override
  ConsumerState<ImportConfirmDialog> createState() =>
      _ImportConfirmDialogState();
}

class _ImportConfirmDialogState extends ConsumerState<ImportConfirmDialog> {
  bool _isImporting = false;

  @override
  /// 构建导入确认对话框，展示各类条目数量并提供确认/取消按钮。
  Widget build(BuildContext context) {
    final data = widget.exportData;

    return AlertDialog(
      title: const Text('检测到配置导入数据'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('剪贴板中包含本应用的配置数据，是否导入？'),
          const SizedBox(height: 16),
          if (data.modelConfigs.isNotEmpty)
            _buildCountRow(
              context,
              icon: Icons.smart_toy_outlined,
              label: '模型配置',
              count: data.modelConfigs.length,
            ),
          if (data.promptTemplates.isNotEmpty)
            _buildCountRow(
              context,
              icon: Icons.text_snippet_outlined,
              label: '前置 Prompt 模板',
              count: data.promptTemplates.length,
            ),
          if (data.fixedPromptSequences.isNotEmpty)
            _buildCountRow(
              context,
              icon: Icons.playlist_play_rounded,
              label: '固定顺序提示词',
              count: data.fixedPromptSequences.length,
            ),
          const SizedBox(height: 12),
          Text(
            '已存在同 id 的条目将被覆盖更新，其余条目不受影响。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isImporting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isImporting ? null : _handleImport,
          child: Text(_isImporting ? '导入中...' : '导入'),
        ),
      ],
    );
  }

  /// 构建单行条目数量展示（图标 + 标签 + 数量）。
  Widget _buildCountRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int count,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label),
          const Spacer(),
          Text(
            '$count 项',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 批量写入三类配置并关闭对话框。
  Future<void> _handleImport() async {
    setState(() => _isImporting = true);

    final data = widget.exportData;

    if (data.modelConfigs.isNotEmpty) {
      await ref
          .read(llmModelConfigsProvider.notifier)
          .upsertAll(data.modelConfigs);
    }
    if (data.promptTemplates.isNotEmpty) {
      await ref
          .read(promptTemplatesProvider.notifier)
          .upsertAll(data.promptTemplates);
    }
    if (data.fixedPromptSequences.isNotEmpty) {
      await ref
          .read(fixedPromptSequencesProvider.notifier)
          .upsertAll(data.fixedPromptSequences);
    }

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }
}

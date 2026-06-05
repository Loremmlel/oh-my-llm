import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/settings_import_executor.dart';
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
          if (data.modelProviders.isNotEmpty)
            _buildCountRow(
              context,
              icon: Icons.hub_outlined,
              label: 'LLM 服务商',
              count: data.modelProviders.length,
            ),
          if (data.memoryPrompts.isNotEmpty)
            _buildCountRow(
              context,
              icon: Icons.memory_rounded,
              label: '记忆总结提示词',
              count: data.memoryPrompts.length,
            ),
          if (data.presetPrompts.isNotEmpty)
            _buildCountRow(
              context,
              icon: Icons.text_snippet_outlined,
              label: '预设 Prompt',
              count: data.presetPrompts.length,
            ),
          if (data.templatePrompts.isNotEmpty)
            _buildCountRow(
              context,
              icon: Icons.dynamic_form_outlined,
              label: '模板提示词',
              count: data.templatePrompts.length,
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
            '与本地内容重复的条目已被过滤，以下均为新增项，导入后不影响已有配置。',
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

  /// 批量写入各类配置并关闭对话框。
  Future<void> _handleImport() async {
    setState(() => _isImporting = true);

    await const SettingsImportExecutor().executeImport(
      ref,
      data: widget.exportData,
    );

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }
}

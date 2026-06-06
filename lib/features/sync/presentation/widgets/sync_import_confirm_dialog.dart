import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/domain/models/settings_export_data.dart';
import '../../application/sync_client_controller.dart';

/// 同步导入确认对话框。
///
/// 展示来自远端设备的配置数据摘要，由用户确认是否覆盖本地配置。
/// 导入逻辑与 [ImportConfirmDialog] 保持一致。
class SyncImportConfirmDialog extends ConsumerStatefulWidget {
  const SyncImportConfirmDialog({
    required this.exportData,
    this.sourceDeviceName,
    super.key,
  });

  final SettingsExportData exportData;
  final String? sourceDeviceName;

  @override
  ConsumerState<SyncImportConfirmDialog> createState() =>
      _SyncImportConfirmDialogState();
}

class _SyncImportConfirmDialogState
    extends ConsumerState<SyncImportConfirmDialog> {
  bool _isImporting = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final data = widget.exportData;

    return AlertDialog(
      title: const Text('确认同步配置'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.sourceDeviceName != null) ...[
            Text('来源设备：${widget.sourceDeviceName}'),
            const SizedBox(height: 12),
          ],
          const Text('即将覆盖本机以下配置：'),
          const SizedBox(height: 12),
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
          if (data.autoRetrySettings != null)
            _buildCountRow(
              context,
              icon: Icons.refresh_rounded,
              label: '自动重试设置',
              count: 1,
            ),
          const SizedBox(height: 12),
          Text(
            '与本地内容重复的条目已被过滤，以上均为新增项，导入后不影响已有配置。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isImporting ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isImporting ? null : _handleImport,
          child: Text(_isImporting ? '导入中...' : '导入'),
        ),
      ],
    );
  }

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

  Future<void> _handleImport() async {
    setState(() {
      _isImporting = true;
      _errorMessage = null;
    });

    try {
      final success = await ref
          .read(syncClientControllerProvider.notifier)
          .executeImport();

      if (mounted) {
        Navigator.of(context).pop(success);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _errorMessage = '导入失败: $e';
        });
      }
    }
  }
}

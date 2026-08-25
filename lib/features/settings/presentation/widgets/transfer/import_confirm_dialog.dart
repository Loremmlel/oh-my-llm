import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/widgets/transfer_summary_list.dart';

import '../../../application/transfer/settings_transfer_coordinator.dart';
import '../../../application/transfer/settings_transfer_types.dart';

/// 配置导入确认对话框。
///
/// 对话框只消费 coordinator 已准备好的 batch，不重新读取剪贴板或解析配置，
/// 以保证用户确认的摘要与实际执行内容一致。
class ImportConfirmDialog extends StatefulWidget {
  const ImportConfirmDialog({required this.batch, super.key});

  final SettingsImportBatch batch;

  @override
  State<ImportConfirmDialog> createState() => _ImportConfirmDialogState();
}

class _ImportConfirmDialogState extends State<ImportConfirmDialog> {
  late SettingsImportBatch _batch;
  bool _isImporting = false;
  bool _sensitiveAcknowledged = false;
  String? _statusMessage;
  List<String> _statusDetails = const [];

  @override
  void initState() {
    super.initState();
    _batch = widget.batch;
  }

  @override
  Widget build(BuildContext context) {
    // 导入期间阻止 system Back 与 barrier tap 关闭对话框；执行完成或失败后
    // 恢复可关闭状态，避免异步写入失去结果落点。
    return PopScope<void>(
      canPop: !_isImporting,
      child: _buildAlertDialog(context),
    );
  }

  Widget _buildAlertDialog(BuildContext context) {
    final summaries = [
      for (final item in _batch.summaryItems)
        TransferSummaryViewItem(
          label: item.label,
          trailingText: item.trailingText,
        ),
    ];

    return AlertDialog(
      title: const Text('检测到配置导入数据'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('剪贴板中包含本应用的配置数据，是否导入？'),
            if (_batch.containsSensitive) ...[
              const SizedBox(height: 12),
              _buildSensitiveWarning(context),
            ],
            const SizedBox(height: 12),
            TransferSummaryList(items: summaries),
            const SizedBox(height: 12),
            Text(
              '以下为待导入的配置摘要，导入后不影响未列出的本地配置。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _statusMessage!,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
              for (final detail in _statusDetails)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(detail),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isImporting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed:
              _isImporting ||
                  (_batch.containsSensitive && !_sensitiveAcknowledged)
              ? null
              : _handleImport,
          child: Text(_isImporting ? '导入中...' : '导入'),
        ),
      ],
    );
  }

  Widget _buildSensitiveWarning(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('包含敏感凭据'),
          const SizedBox(height: 4),
          const Text('服务商 API Key 或自定义 Header 值可能包含 token。'),
          Row(
            children: [
              Checkbox(
                value: _sensitiveAcknowledged,
                onChanged: _isImporting
                    ? null
                    : (value) => setState(
                        () => _sensitiveAcknowledged = value ?? false,
                      ),
              ),
              const Expanded(child: Text('我确认导入这些敏感内容')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleImport() async {
    setState(() {
      _isImporting = true;
      _statusMessage = null;
      _statusDetails = const [];
    });

    try {
      final result = await _batch.execute(
        confirmedSensitive: _sensitiveAcknowledged,
      );
      if (!mounted) return;

      if (result is SettingsImportSuccess) {
        Navigator.of(context).pop(true);
        return;
      }
      if (result is SettingsImportStalePreview) {
        setState(() {
          _batch = result.refreshedBatch;
          _isImporting = false;
          _sensitiveAcknowledged = false;
          _statusMessage = '本地设置已变化，请重新确认';
          _statusDetails = const [];
        });
        return;
      }
      if (result is SettingsImportPartialFailure) {
        setState(() {
          _isImporting = false;
          _statusMessage = '部分配置已导入';
          _statusDetails = [
            if (result.completed.isNotEmpty) '已完成：${_labels(result.completed)}',
            '失败：${result.failedLabel}',
            if (result.notAttempted.isNotEmpty)
              '未执行：${_labels(result.notAttempted)}',
            result.safeReason,
          ];
        });
        return;
      }
      if (result is SettingsImportFailure) {
        setState(() {
          _isImporting = false;
          _statusMessage = result.safeReason;
          _statusDetails = const [];
        });
        return;
      }
      if (result is SettingsImportSensitiveConfirmationRequired) {
        setState(() {
          _isImporting = false;
          _sensitiveAcknowledged = false;
          _statusMessage = '导入敏感内容前需要确认';
          _statusDetails = const [];
        });
        return;
      }
      if (result is SettingsImportAlreadyConsumed) {
        setState(() {
          _isImporting = false;
          _statusMessage = '导入未完成，请重新准备';
          _statusDetails = const [];
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _statusMessage = '导入未完成，请重试';
        _statusDetails = const [];
      });
    }
  }

  String _labels(Iterable<SettingsTransferSummaryItem> items) =>
      items.map((item) => item.label).join('、');
}

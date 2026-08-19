import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/ports/settings_sync_facade.dart';
import '../../application/sync_client_controller.dart';

/// 同步导入确认对话框。
class SyncImportConfirmDialog extends ConsumerStatefulWidget {
  const SyncImportConfirmDialog({
    required this.preparedImport,
    this.sourceDeviceName,
    super.key,
  });

  final SettingsSyncPreparedImport preparedImport;
  final String? sourceDeviceName;

  @override
  ConsumerState<SyncImportConfirmDialog> createState() =>
      _SyncImportConfirmDialogState();
}

class _SyncImportConfirmDialogState
    extends ConsumerState<SyncImportConfirmDialog> {
  bool _isImporting = false;
  bool _sensitiveAcknowledged = false;
  String? _errorMessage;
  late SettingsSyncPreparedImport _preparedImport = widget.preparedImport;

  List<SettingsSyncSummaryItem> get _summaries => _preparedImport.summaries;

  bool get _containsSensitive => _preparedImport.containsSensitive;

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_isImporting,
      child: _buildAlertDialog(context),
    );
  }

  Widget _buildAlertDialog(BuildContext context) {
    final hasSensitiveData = _containsSensitive;
    final summaries = _summaries;

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
          const Text('即将导入本机以下配置：'),
          if (hasSensitiveData) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('包含敏感凭据'),
                  const SizedBox(height: 4),
                  const Text('服务商 API Key 或自定义请求头可能包含 token。'),
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
            ),
          ],
          const SizedBox(height: 12),
          for (final summary in summaries) _buildSummaryRow(context, summary),
          if (summaries.isEmpty) const Text('没有可导入的变化'),
          const SizedBox(height: 12),
          Text(
            '与本地内容重复的条目已被过滤，以上均为待导入变化。',
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
          onPressed: _isImporting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed:
              _isImporting || (hasSensitiveData && !_sensitiveAcknowledged)
              ? null
              : _handleImport,
          child: Text(_isImporting ? '导入中...' : '导入'),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(
    BuildContext context,
    SettingsSyncSummaryItem summary,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.settings_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(summary.label)),
          Text(
            summary.trailingText,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
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
      final result = await ref
          .read(syncClientControllerProvider.notifier)
          .executePreparedImport(confirmedSensitive: _sensitiveAcknowledged);
      if (!mounted) return;
      switch (result) {
        case SettingsSyncImportSuccess():
          Navigator.of(context).pop(true);
        case SettingsSyncImportSensitiveConfirmationRequired():
          setState(() {
            _isImporting = false;
            _sensitiveAcknowledged = false;
            _errorMessage = '请确认导入敏感内容后重试';
          });
        case SettingsSyncImportStalePreview(:final refreshedImport):
          setState(() {
            _isImporting = false;
            _preparedImport = refreshedImport;
            _sensitiveAcknowledged = false;
            _errorMessage = '本地设置已变化，请重新确认';
          });
        case SettingsSyncImportFailure(:final safeReason):
          setState(() {
            _isImporting = false;
            _errorMessage = safeReason;
          });
        case SettingsSyncImportPartialFailure(
          :final failedLabel,
          :final safeReason,
        ):
          setState(() {
            _isImporting = false;
            _errorMessage = '部分配置已导入：$failedLabel。$safeReason';
          });
        case SettingsSyncImportAlreadyConsumed():
          setState(() {
            _isImporting = false;
            _errorMessage = '导入批次已处理，请重新同步';
          });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _errorMessage = '导入未完成，请重试';
      });
    }
  }
}

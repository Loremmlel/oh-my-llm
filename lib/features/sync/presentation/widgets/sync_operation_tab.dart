import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/widgets/notification_bubble/notification_bubble_context_ext.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/shared/settings_section_card.dart';

import '../../application/ports/settings_sync_facade.dart';
import '../../application/sync_client_controller.dart';
import 'sync_import_confirm_dialog.dart';

/// 同步页面 Tab 2：同步操作，选择同步内容并执行导入。
class SyncOperationTab extends ConsumerStatefulWidget {
  const SyncOperationTab({super.key});

  @override
  ConsumerState<SyncOperationTab> createState() => _SyncOperationTabState();
}

class _SyncOperationTabState extends ConsumerState<SyncOperationTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _isConnectedOrError(SyncPhase phase) {
    return phase == SyncPhase.connected ||
        phase == SyncPhase.syncing ||
        phase == SyncPhase.received ||
        phase == SyncPhase.noNewData ||
        phase == SyncPhase.imported ||
        phase == SyncPhase.error;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final clientState = ref.watch(syncClientControllerProvider);

    ref.listen<SyncClientState>(syncClientControllerProvider, (prev, next) {
      final enteredReceived =
          prev?.phase == SyncPhase.syncing && next.phase == SyncPhase.received;
      final enteredNoNewData =
          prev?.phase == SyncPhase.syncing && next.phase == SyncPhase.noNewData;
      if (enteredReceived && next.preparedImport != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            _showImportDialog(
              context,
              ref,
              next.preparedImport!,
              next.sourceDeviceName,
            );
          }
        });
      } else if (enteredNoNewData) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            context.showBubble('远端配置与本机完全一致，无需导入');
          }
        });
      }
    });

    if (clientState.server == null || !_isConnectedOrError(clientState.phase)) {
      return _buildNotConnectedView(context, clientState);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSyncStatusCard(context, ref, clientState),
        const SizedBox(height: 16),
        if (clientState.phase == SyncPhase.error) ...[
          _buildErrorMessage(context, ref, clientState),
        ] else ...[
          _buildGroupCard(context, ref, clientState),
          const SizedBox(height: 16),
          _buildSyncButton(context, ref, clientState),
          if (clientState.phase == SyncPhase.imported) ...[
            const SizedBox(height: 16),
            _buildImportedMessage(context),
          ],
        ],
      ],
    );
  }

  /// 未连接占位视图；error 态（断开/未发现）展示具体错误文案，其余保持引导文案。
  Widget _buildNotConnectedView(BuildContext context, SyncClientState state) {
    final theme = Theme.of(context);
    final disconnected = state.phase == SyncPhase.error;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              disconnected ? Icons.error_outline : Icons.cloud_off_rounded,
              size: 48,
              color: disconnected
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              disconnected
                  ? (state.errorMessage ?? '发生未知错误')
                  : '请先在「连接」标签页中连接到服务端',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: disconnected
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncStatusCard(
    BuildContext context,
    WidgetRef ref,
    SyncClientState state,
  ) {
    final theme = Theme.of(context);

    return SettingsSectionCard(
      title: '连接状态',
      description: state.isPaired ? '已配对的安全同步连接' : '请先在连接页输入服务端配对码',
      child: Row(
        children: [
          if (state.phase == SyncPhase.syncing) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text('正在同步配置...', style: theme.textTheme.bodyMedium),
          ] else if (state.phase == SyncPhase.error) ...[
            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '同步出错',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ] else ...[
            Icon(Icons.check_circle, color: Colors.green.shade400, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${state.isPaired ? '已配对' : '尚未配对'}：${state.sourceDeviceName ?? '未知设备'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorMessage(
    BuildContext context,
    WidgetRef ref,
    SyncClientState state,
  ) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            state.errorMessage ?? '发生未知错误',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
        const SizedBox(height: 12),
        _buildResyncButton(context, ref),
      ],
    );
  }

  Widget _buildGroupCard(
    BuildContext context,
    WidgetRef ref,
    SyncClientState state,
  ) {
    final notifier = ref.read(syncClientControllerProvider.notifier);
    final availableIds = state.availableGroups.map((group) => group.id).toSet();
    final allSelected =
        state.selectedGroups.length == availableIds.length &&
        state.selectedGroups.containsAll(availableIds);

    return SettingsSectionCard(
      title: '同步内容',
      description: '选择要从服务端同步到本机的配置分组',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('选择分组', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              TextButton(
                onPressed: allSelected ? null : notifier.selectAllGroups,
                child: const Text('全选'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...state.availableGroups.map((group) {
            return CheckboxListTile(
              title: Text(
                group.sensitivity == SettingsSyncSensitivity.credentialBearing
                    ? '${group.label}（含敏感凭据）'
                    : group.label,
              ),
              value: state.selectedGroups.contains(group.id),
              onChanged: (_) => notifier.toggleGroup(group.id),
              dense: true,
              contentPadding: EdgeInsets.zero,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSyncButton(
    BuildContext context,
    WidgetRef ref,
    SyncClientState state,
  ) {
    final isSyncing = state.phase == SyncPhase.syncing;
    final needsSensitiveConfirmation = state.availableGroups.any(
      (group) =>
          state.selectedGroups.contains(group.id) &&
          group.sensitivity == SettingsSyncSensitivity.credentialBearing,
    );

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: isSyncing || state.selectedGroups.isEmpty || !state.isPaired
            ? null
            : () async {
                if (needsSensitiveConfirmation &&
                    !state.sensitiveRequestConfirmed) {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => AlertDialog(
                      title: const Text('确认接收敏感凭据'),
                      content: const Text(
                        '服务商 API Key 或自定义请求头可能包含 token。仅在确认了解风险后继续。',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('确认接收'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true || !context.mounted) return;
                  ref
                      .read(syncClientControllerProvider.notifier)
                      .confirmSensitiveRequest();
                }
                await ref
                    .read(syncClientControllerProvider.notifier)
                    .requestSync();
              },
        icon: const Icon(Icons.sync_rounded),
        label: Text(isSyncing ? '同步中...' : '开始同步'),
      ),
    );
  }

  Widget _buildResyncButton(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () =>
            ref.read(syncClientControllerProvider.notifier).resetToConnected(),
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('重新同步'),
      ),
    );
  }

  Widget _buildImportedMessage(BuildContext context) {
    final successColor = Theme.of(context).colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: successColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: successColor),
          const SizedBox(width: 8),
          Text('配置已成功导入', style: TextStyle(color: successColor)),
        ],
      ),
    );
  }

  Future<void> _showImportDialog(
    BuildContext context,
    WidgetRef ref,
    SettingsSyncPreparedImport preparedImport,
    String? sourceDeviceName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SyncImportConfirmDialog(
        preparedImport: preparedImport,
        sourceDeviceName: sourceDeviceName,
      ),
    );

    if (confirmed == true) {
      if (context.mounted) {
        context.showSuccessBubble('配置已导入');
      }
    } else {
      final currentPhase = ref.read(syncClientControllerProvider).phase;
      if (currentPhase != SyncPhase.error) {
        ref.read(syncClientControllerProvider.notifier).resetToConnected();
      }
    }
  }
}

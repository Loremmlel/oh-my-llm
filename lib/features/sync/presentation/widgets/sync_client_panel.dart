import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/domain/models/settings_export_data.dart';
import '../../../settings/presentation/widgets/settings_section_card.dart';
import '../../application/network_interface_provider.dart';
import '../../application/sync_client_controller.dart';
import '../../domain/models/sync_types.dart';
import 'sync_import_confirm_dialog.dart';

/// 同步页面中客户端模式的控制面板。
class SyncClientPanel extends ConsumerWidget {
  const SyncClientPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientState = ref.watch(syncClientControllerProvider);

    ref.listen<SyncClientState>(syncClientControllerProvider, (prev, next) {
      if (next.phase == SyncPhase.received && next.deduplicatedData != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            _showImportDialog(context, ref, next.deduplicatedData!, next.sourceDeviceName);
          }
        });
      }
    });

    return SettingsSectionCard(
      title: '发现服务端',
      description: '搜索局域网内正在广播的服务端，同步其配置到本机',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPhaseStatus(context, ref, clientState),
          const SizedBox(height: 16),
          _buildActionButtons(context, ref, clientState),
          if (clientState.phase == SyncPhase.connected) ...[
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            _buildCategorySelector(context, ref, clientState),
            const SizedBox(height: 16),
            _buildSyncButton(context, ref, clientState),
          ],
          if (clientState.phase == SyncPhase.done) ...[
            const SizedBox(height: 16),
            _buildDoneMessage(context),
          ],
        ],
      ),
    );
  }

  Widget _buildPhaseStatus(
    BuildContext context,
    WidgetRef ref,
    SyncClientState state,
  ) {
    final theme = Theme.of(context);

    switch (state.phase) {
      case SyncPhase.idle:
        return const SizedBox.shrink();
      case SyncPhase.discovering:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text('正在搜索服务端...', style: theme.textTheme.bodyMedium),
              ],
            ),
            // 显示当前监听接口
            _buildListeningInterfaces(context, ref),
          ],
        );
      case SyncPhase.connected:
        return Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade400, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '已连接：${state.sourceDeviceName ?? '未知设备'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      case SyncPhase.syncing:
        return Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text('正在同步配置...', style: theme.textTheme.bodyMedium),
          ],
        );
      case SyncPhase.received:
        return const SizedBox.shrink();
      case SyncPhase.noNewData:
        return Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange.shade400, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '远端配置与本机完全一致，无需导入',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.orange.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      case SyncPhase.done:
        return Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade400, size: 20),
            const SizedBox(width: 8),
            Text('同步完成', style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.green.shade700,
              fontWeight: FontWeight.w600,
            )),
          ],
        );
      case SyncPhase.error:
        return Text(
          state.errorMessage ?? '发生未知错误',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        );
    }
  }

  Widget _buildActionButtons(
    BuildContext context,
    WidgetRef ref,
    SyncClientState state,
  ) {
    final notifier = ref.read(syncClientControllerProvider.notifier);

    switch (state.phase) {
      case SyncPhase.idle:
      case SyncPhase.error:
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: notifier.startDiscovery,
            icon: const Icon(Icons.radar_rounded),
            label: const Text('发现服务端'),
          ),
        );
      case SyncPhase.discovering:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: notifier.cancelAndReset,
            child: const Text('取消搜索'),
          ),
        );
      case SyncPhase.connected:
      case SyncPhase.syncing:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: notifier.cancelAndReset,
                child: const Text('断开连接'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: notifier.startDiscovery,
                child: const Text('重新搜索'),
              ),
            ),
          ],
        );
      case SyncPhase.received:
      case SyncPhase.noNewData:
      case SyncPhase.done:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: notifier.cancelAndReset,
            child: const Text('重新开始'),
          ),
        );
    }
  }

  Widget _buildCategorySelector(
    BuildContext context,
    WidgetRef ref,
    SyncClientState state,
  ) {
    final notifier = ref.read(syncClientControllerProvider.notifier);
    final allSelected = state.selectedCategories.length == SyncCategory.values.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '同步内容',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            TextButton(
              onPressed: allSelected ? null : notifier.selectAllCategories,
              child: const Text('全选'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...SyncCategory.values.map((category) {
          return CheckboxListTile(
            title: Text(category.label),
            value: state.selectedCategories.contains(category),
            onChanged: (_) => notifier.toggleCategory(category),
            dense: true,
            contentPadding: EdgeInsets.zero,
          );
        }),
      ],
    );
  }

  Widget _buildSyncButton(
    BuildContext context,
    WidgetRef ref,
    SyncClientState state,
  ) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: state.selectedCategories.isEmpty
            ? null
            : () => ref.read(syncClientControllerProvider.notifier).requestSync(),
        icon: const Icon(Icons.sync_rounded),
        label: const Text('开始同步'),
      ),
    );
  }

  Widget _buildDoneMessage(BuildContext context) {
    final theme = Theme.of(context);
    final successColor = theme.colorScheme.primary;

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
          Text(
            '配置已成功导入',
            style: TextStyle(color: successColor),
          ),
        ],
      ),
    );
  }

  Widget _buildListeningInterfaces(
    BuildContext context,
    WidgetRef ref,
  ) {
    final interfacesAsync = ref.watch(availableInterfacesProvider);
    return interfacesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (interfaces) {
        if (interfaces.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '监听于: ${interfaces.map((i) => i.ip).join(', ')}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        );
      },
    );
  }

  Future<void> _showImportDialog(
    BuildContext context,
    WidgetRef ref,
    SettingsExportData data,
    String? sourceDeviceName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SyncImportConfirmDialog(
        exportData: data,
        sourceDeviceName: sourceDeviceName,
      ),
    );

    if (confirmed == true) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('配置已导入')),
        );
      }
    } else {
      ref.read(syncClientControllerProvider.notifier).resetToConnected();
    }
  }
}

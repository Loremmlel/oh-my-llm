import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/presentation/widgets/settings_section_card.dart';
import '../../application/network_interface_provider.dart';
import '../../application/sync_client_controller.dart';
import '../../application/sync_server_controller.dart';
import 'interface_selector.dart';

/// 同步页面 Tab 1：连接管理，包含服务端广播与客户端发现/连接。
class SyncConnectionTab extends ConsumerStatefulWidget {
  const SyncConnectionTab({super.key});

  @override
  ConsumerState<SyncConnectionTab> createState() => _SyncConnectionTabState();
}

class _SyncConnectionTabState extends ConsumerState<SyncConnectionTab>
    with AutomaticKeepAliveClientMixin {
  bool _isServerMode = false;
  late TextEditingController _nameController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final serverState = ref.read(syncServerControllerProvider);
    _nameController = TextEditingController(text: serverState.deviceName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _onModeChanged(bool serverMode) {
    if (serverMode == _isServerMode) return;
    ref.read(syncClientControllerProvider.notifier).cancelAndReset();
    setState(() => _isServerMode = serverMode);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildModeSelector(),
        const SizedBox(height: 16),
        if (_isServerMode) _buildServerSection() else _buildClientSection(),
      ],
    );
  }

  Widget _buildModeSelector() {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(
          value: false,
          label: Text('作为客户端'),
          icon: Icon(Icons.download_rounded),
        ),
        ButtonSegment(
          value: true,
          label: Text('作为服务端'),
          icon: Icon(Icons.upload_rounded),
        ),
      ],
      selected: {_isServerMode},
      onSelectionChanged: (selected) => _onModeChanged(selected.first),
    );
  }

  // ── 客户端模式 ──────────────────────────────────────────────

  Widget _buildClientSection() {
    final clientState = ref.watch(syncClientControllerProvider);

    return SettingsSectionCard(
      title: '发现服务端',
      description: '搜索局域网内正在广播的服务端，同步其配置到本机',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildClientPhaseStatus(clientState),
          const SizedBox(height: 16),
          _buildClientActionButtons(clientState),
        ],
      ),
    );
  }

  Widget _buildClientPhaseStatus(SyncClientState state) {
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
            _buildListeningInterfaces(),
          ],
        );
      case SyncPhase.connected:
      case SyncPhase.imported:
      case SyncPhase.noNewData:
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
      case SyncPhase.error:
        return Text(
          state.errorMessage ?? '发生未知错误',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        );
    }
  }

  Widget _buildClientActionButtons(SyncClientState state) {
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
      case SyncPhase.received:
      case SyncPhase.noNewData:
      case SyncPhase.imported:
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
    }
  }

  Widget _buildListeningInterfaces() {
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

  // ── 服务端模式 ──────────────────────────────────────────────

  Widget _buildServerSection() {
    final serverState = ref.watch(syncServerControllerProvider);
    final theme = Theme.of(context);

    return SettingsSectionCard(
      title: '服务端广播',
      description: '启动后，局域网内其他设备可以发现本机并同步配置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '设备名称',
              border: OutlineInputBorder(),
            ),
            enabled: !serverState.isRunning,
            onSubmitted: (value) {
              ref
                  .read(syncServerControllerProvider.notifier)
                  .updateDeviceName(value);
            },
          ),
          const SizedBox(height: 16),
          if (!serverState.isRunning) ...[
            const InterfaceSelector(),
            const SizedBox(height: 16),
          ],
          if (serverState.isRunning) ...[
            Row(
              children: [
                Icon(Icons.circle, color: Colors.green.shade400, size: 12),
                const SizedBox(width: 8),
                Text(
                  '正在广播',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '设备名称：${serverState.deviceName}',
              style: theme.textTheme.bodyMedium,
            ),
            if (serverState.httpPort != null) ...[
              const SizedBox(height: 4),
              Text(
                '服务端口：${serverState.httpPort}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (serverState.selectedInterface != null) ...[
              const SizedBox(height: 4),
              Text(
                '广播网卡：${serverState.selectedInterface!.label}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '广播地址：${serverState.selectedInterface!.broadcast}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (serverState.servedRequestCount > 0) ...[
              const SizedBox(height: 4),
              Text(
                '已完成 ${serverState.servedRequestCount} 次同步请求',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () =>
                    ref.read(syncServerControllerProvider.notifier).stop(),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('停止广播'),
              ),
            ),
          ] else ...[
            if (serverState.lastError != null) ...[
              Text(
                serverState.lastError!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () =>
                    ref.read(syncServerControllerProvider.notifier).start(),
                icon: const Icon(Icons.sensors_rounded),
                label: const Text('启动广播'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

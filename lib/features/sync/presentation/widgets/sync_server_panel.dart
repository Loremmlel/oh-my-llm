import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/presentation/widgets/settings_section_card.dart';
import '../../application/sync_server_controller.dart';

/// 同步页面中服务端模式的控制面板。
class SyncServerPanel extends ConsumerStatefulWidget {
  const SyncServerPanel({super.key});

  @override
  ConsumerState<SyncServerPanel> createState() => _SyncServerPanelState();
}

class _SyncServerPanelState extends ConsumerState<SyncServerPanel> {
  late TextEditingController _nameController;

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

  @override
  Widget build(BuildContext context) {
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/network_interface_provider.dart';

/// 网络接口选择器，用于在服务端模式下选择广播的网段。
///
/// 列出本机所有 IPv4 接口（名称、IP、广播地址），默认选中第一个。
/// 无接口时显示警告提示。
class InterfaceSelector extends ConsumerWidget {
  const InterfaceSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interfacesAsync = ref.watch(availableInterfacesProvider);

    return interfacesAsync.when(
      loading: () => const SizedBox(
        height: 48,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => Text(
        '获取网络接口失败',
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontSize: 13,
        ),
      ),
      data: (interfaces) {
        if (interfaces.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.orange.shade700, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '未检测到可用网络接口，将使用全局广播',
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final selectedIndex = ref.watch(selectedInterfaceIndexProvider);
        final safeIndex = selectedIndex.clamp(0, interfaces.length - 1);
        final selectedIface = interfaces[safeIndex];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InputDecorator(
              decoration: const InputDecoration(
                labelText: '广播网卡',
                border: OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: safeIndex,
                  isExpanded: true,
                  isDense: true,
                  items: interfaces.asMap().entries.map((entry) {
                    final i = entry.key;
                    final iface = entry.value;
                    return DropdownMenuItem(
                      value: i,
                      child: Tooltip(
                        message: '广播地址: ${iface.broadcast}',
                        child: Text(
                          '${iface.name} — ${iface.ip}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (index) {
                    if (index != null) {
                      ref
                          .read(selectedInterfaceIndexProvider.notifier)
                          .select(index);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '广播地址: ${selectedIface.broadcast}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        );
      },
    );
  }
}

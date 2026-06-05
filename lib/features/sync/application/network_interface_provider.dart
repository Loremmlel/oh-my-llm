import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/network_interface_info.dart';
import '../domain/models/network_interface_utils.dart';

/// 本机可用的 IPv4 网络接口列表（异步加载）。
final availableInterfacesProvider =
    FutureProvider<List<NetworkInterfaceInfo>>((ref) {
  return NetworkInterfaceUtils.getAvailableInterfaces();
});

/// 用户在服务端模式下选择的广播接口索引。
class _SelectedInterfaceIndex extends Notifier<int> {
  @override
  int build() => 0;

  /// 更新选中的接口索引。
  void select(int index) => state = index;
}

/// 用户选择的广播网卡索引，默认为 0（第一个）。
final selectedInterfaceIndexProvider =
    NotifierProvider<_SelectedInterfaceIndex, int>(
  _SelectedInterfaceIndex.new,
);

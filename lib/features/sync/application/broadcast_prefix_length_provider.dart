import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/shared_preferences_provider.dart';
import '../domain/models/broadcast_prefix_length.dart';

/// SharedPreferences 中子网掩码的键名。
const String _prefixLengthKey = 'sync.broadcast_prefix_length';

/// 用户在 UI 选择的广播子网掩码长度，默认为 [BroadcastPrefixLength.p24]。
///
/// 持久化到 SharedPreferences，下次启动自动恢复；非法值或缺失时回退到默认 /24。
class SelectedBroadcastPrefixLength extends Notifier<BroadcastPrefixLength> {
  @override
  BroadcastPrefixLength build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return BroadcastPrefixLength.fromStorage(prefs.getInt(_prefixLengthKey));
  }

  /// 切换子网掩码；与当前值相同则跳过，避免无意义写入。
  void select(BroadcastPrefixLength value) {
    if (state == value) return;
    state = value;
    ref.read(sharedPreferencesProvider).setInt(_prefixLengthKey, value.toStorage());
  }
}

final selectedBroadcastPrefixLengthProvider =
    NotifierProvider<SelectedBroadcastPrefixLength, BroadcastPrefixLength>(
  SelectedBroadcastPrefixLength.new,
);

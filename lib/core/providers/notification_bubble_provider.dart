import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/notification_bubble_data.dart';

/// 全局通知气泡 Provider。
///
/// 用法：
/// ```dart
/// ref.read(notificationBubblesProvider.notifier).show(message: '已收藏');
/// ```
final notificationBubblesProvider =
    NotifierProvider<NotificationBubbleNotifier, List<NotificationBubbleData>>(
      NotificationBubbleNotifier.new,
    );

/// 通知气泡状态管理器。
///
/// 负责通知的增删、最多 3 条堆叠限制、自动消失计时。
class NotificationBubbleNotifier extends Notifier<List<NotificationBubbleData>> {
  /// 各通知的自动消失计时器，按 ID 索引。
  final Map<String, Timer> _timers = {};

  @override
  List<NotificationBubbleData> build() {
    ref.onDispose(_cancelAllTimers);
    return [];
  }

  /// 显示一条通知。
  ///
  /// [type] 默认为 [NotificationBubbleType.info]。
  /// [action] 可选操作按钮，点击后气泡自动关闭。
  /// [duration] 自定义停留时间，null 表示使用类型默认值。
  void show({
    required String message,
    NotificationBubbleType type = NotificationBubbleType.info,
    NotificationBubbleAction? action,
    Duration? duration,
  }) {
    final data = NotificationBubbleData(
      message: message,
      type: type,
      action: action,
      duration: duration,
    );

    // 最多 3 条可见，超出时最旧的通知被直接丢弃且不做出场动画。
    final maxVisible = 3;

    if (state.length >= maxVisible) {
      final oldest = state.last;
      _cancelTimer(oldest.id);
      state = [data, ...state.sublist(0, maxVisible - 1)];
    } else {
      state = [data, ...state];
    }

    _scheduleDismiss(data);
  }

  /// 手动关闭某条通知。
  ///
  /// ID 不存在时直接返回，避免无意义的状态重建。
  void dismiss(String id) {
    if (!state.any((d) => d.id == id)) return;
    _cancelTimer(id);
    state = state.where((d) => d.id != id).toList();
  }

  /// 启动自动消失计时器；通知如有操作按钮则延迟更久。
  void _scheduleDismiss(NotificationBubbleData data) {
    _cancelTimer(data.id);
    _timers[data.id] = Timer(data.effectiveDuration, () {
      dismiss(data.id);
    });
  }

  void _cancelTimer(String id) {
    _timers[id]?.cancel();
    _timers.remove(id);
  }

  void _cancelAllTimers() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}

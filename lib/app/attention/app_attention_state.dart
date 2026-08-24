import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

/// 应用注意力快照：生命周期 + 窗口焦点 + 当前路由。
///
/// 由 [AppAttentionObserver]（见 `app_attention_observer.dart`）统一更新；
/// 终态通知深模块只读取本快照做抑制判定，不自行监听 Flutter/window API。
final class AppAttentionState extends Equatable {
  const AppAttentionState({
    required this.lifecycleState,
    required this.windowFocused,
    required this.location,
  });

  /// 启动初值：`detached`、未聚焦、空 `Uri`。
  ///
  /// 有意选择「可能多发、不能漏发」：异步焦点查询完成前不得假定 attentive，
  /// 首个真实 lifecycle/route/focus 快照到达后自然收敛；不得改成虚假的
  /// 前台聚焦状态（`Uri()` 非 const，用 getter 提供）。
  static AppAttentionState get initial => AppAttentionState(
    lifecycleState: AppLifecycleState.detached,
    windowFocused: false,
    location: Uri(),
  );

  /// Flutter 生命周期状态；首个事件到达前保持 detached。
  final AppLifecycleState lifecycleState;

  /// 窗口是否聚焦；Android/no-op 窗口实现恒为 true。
  final bool windowFocused;

  /// GoRouter 当前路由（来自 routeInformationProvider 的 Uri）。
  final Uri location;

  /// 宿主是否正在前台且窗口聚焦。
  ///
  /// Windows 只有 `lifecycle == resumed && windowFocused == true` 才算
  /// attentive；不满足时终态通知一律展示。
  bool get hostIsAttentive =>
      lifecycleState == AppLifecycleState.resumed && windowFocused;

  @override
  List<Object?> get props => [lifecycleState, windowFocused, location];
}

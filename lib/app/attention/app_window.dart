/// 应用窗口的抽象端口：焦点查询/监听与恢复聚焦。
///
/// 生产由平台 composition 绑定：Windows 包装 `window_manager`，
/// Android/其余平台绑定 no-op（恒视为 focused）。终态通知深模块只经注意力
/// 快照与 restoreHost 回调消费本端口，不直接持有窗口 API。
abstract interface class AppWindow {
  /// 焦点变化流（true = 获得焦点）。
  Stream<bool> get focusChanges;

  /// 异步查询当前是否聚焦；首个真实快照到达前不得据此假定 attentive。
  Future<bool> isFocused();

  /// 恢复窗口（show/restore）并聚焦；供通知点击后的宿主恢复。
  Future<void> restoreAndFocus();

  /// 释放资源；幂等。
  Future<void> dispose();
}

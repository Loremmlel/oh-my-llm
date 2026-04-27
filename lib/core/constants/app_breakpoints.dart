/// 响应式布局断点常量。
///
/// - [compact]：宽度低于此值时切换为紧凑布局（底部导航条 + 抽屉）。
/// - [expanded]：宽度高于此值时展示宽屏侧边面板（聊天页会话历史列表等）。
final class AppBreakpoints {
  const AppBreakpoints._();

  static const double compact = 720;
  static const double expanded = 1100;
}

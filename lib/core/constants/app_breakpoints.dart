/// 响应式布局断点常量。
///
/// - [compact]：宽度低于此值时切换为紧凑布局（底部导航条 + endDrawer）。
///   宽度 >= 720px 时展示宽屏布局（NavigationRail + ActivityBar + SidebarPanel）。
final class AppBreakpoints {
  const AppBreakpoints._();

  static const double compact = 720;
}

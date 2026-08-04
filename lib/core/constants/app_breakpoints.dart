import 'package:flutter/widgets.dart';

/// 响应式布局断点常量。
///
/// - [compact]：宽度低于此值时切换为紧凑布局（底部导航条 + endDrawer）。
///   宽度 >= 720px 时展示宽屏布局（NavigationRail + ActivityBar + SidebarPanel）。
final class AppBreakpoints {
  const AppBreakpoints._();

  static const double compact = 720;

  /// 当前窗口宽度是否低于 [compact] 断点（紧凑/移动端布局）。
  ///
  /// 供无外部 isCompact 参数的组件在 build 内自行判断，避免 prop drilling。
  /// 使用 [MediaQuery.sizeOf] 而非 [MediaQuery.of] 以避免不必要重建。
  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compact;
}

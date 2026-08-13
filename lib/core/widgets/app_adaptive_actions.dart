import 'package:flutter/widgets.dart';

import 'package:oh_my_llm/core/constants/app_breakpoints.dart';

/// 按宽度断点选择动作列表的响应式原语。
///
/// [resolve] 接收父组件可用宽度：`width < breakpoint` 返回紧凑动作，
/// `width >= breakpoint`（等号属宽侧）返回宽侧动作。
final class AppAdaptiveActions {
  const AppAdaptiveActions({
    required this.wideActions,
    required this.compactActions,
    this.breakpoint = AppBreakpoints.shellNavigation,
  });

  final List<Widget> wideActions;
  final List<Widget> compactActions;
  final double breakpoint;

  List<Widget> resolve(double availableWidth) =>
      availableWidth < breakpoint ? compactActions : wideActions;
}

import 'package:flutter/widgets.dart';

/// 按布局职责定义的响应式断点。
///
/// 每个 token 只描述一种布局切换；判定统一为「小于断点走紧凑/单栏/近全宽分支，
/// 大于等于断点走宽侧/双栏/比例限宽分支」，等号永远属于宽侧。
/// 不要在调用处改写比较方向，也不要再引入 `compact`/`isCompact` 兼容别名。
final class AppBreakpoints {
  const AppBreakpoints._();

  /// 应用壳导航断点，接收窗口级宽度（顶层可用宽度）。
  ///
  /// 控制底部导航与侧向导航之间的切换；常驻辅助内容另受工作区尺寸约束。
  /// `width >= 720` 进入宽侧导航，等号属宽侧。
  static const double shellNavigation = 720.0;

  /// 常驻工作区侧栏需要给正文与历史列表同时保留可用空间。
  static const double workspaceSidebarWidth = 1100.0;
  static const double workspaceSidebarHeight = 640.0;

  /// 通用内容区主从布局默认双栏阈值，接收父组件分配宽度。
  ///
  /// 作为 [AdaptiveMasterDetailLayout] 的默认 `breakpoint` 使用，等号属宽侧
  /// （`width >= 840` 开始 master/detail 双栏）。调用方可注入自定义值。
  static const double contentMasterDetail = 840.0;

  /// 两个 Chat 主从选择对话框（检查点、消息过滤）的双栏阈值，接收父约束。
  ///
  /// `width >= 760` 开始 master/detail，等号属宽侧。
  static const double dialogMasterDetail = 760.0;

  /// Chat composer 操作行紧凑/完整阈值，接收 composer 父约束宽度。
  ///
  /// `width >= 680` 显示完整操作行（思考/重试/固定顺序/过滤），等号属宽侧。
  static const double formActions = 680.0;

  /// 两个 Settings 多面板表单（预设 Prompt、固定顺序提示词）的双栏阈值，
  /// 接收表单父约束宽度。`width >= 900` 开始 master/detail，等号属宽侧。
  static const double formMasterDetail = 900.0;

  /// 消息阅读区窄边距/标准边距阈值，接收消息父约束宽度。
  ///
  /// `width >= 600` 使用标准边距和阅读限宽，等号属宽侧。
  static const double messageBubble = 600.0;

  static bool useCompactShell(double availableWidth) =>
      availableWidth < shellNavigation;

  static bool useCompactFormActions(double availableWidth) =>
      availableWidth < formActions;

  static bool useFullWidthMessageBubble(double availableWidth) =>
      availableWidth < messageBubble;

  static bool isCompactShell(BuildContext context) =>
      useCompactShell(MediaQuery.sizeOf(context).width);
}

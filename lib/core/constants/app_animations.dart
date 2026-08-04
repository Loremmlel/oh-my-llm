/// 应用统一的 UI 动画时长。
///
/// 仅收纳跨组件复用的同语义动画时长；防抖/节流等业务间隔
/// 由各 controller 自行命名，不在此处统一。
final class AppAnimations {
  const AppAnimations._();

  /// 快速 UI 过渡：pill toggle 配色、面板展开/收起、指示点尺寸变化等。
  static const Duration quickTransition = Duration(milliseconds: 167);
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/widgets/app_adaptive_actions.dart';
import '../navigation/app_destination.dart';

/// 应用顶层页面共用的脚手架。
///
/// 它负责在桌面侧边栏布局和紧凑底部导航布局之间切换，让业务页面只需
/// 关注页面内容和可选动作。
class AppShellScaffold extends StatelessWidget {
  const AppShellScaffold({
    required this.currentDestination,
    required this.title,
    required this.body,
    this.actions,
    this.adaptiveActions,
    this.endDrawer,
    this.hasLocalBackTarget = false,
    this.onLocalBack,
    super.key,
  }) : assert(!hasLocalBackTarget || onLocalBack != null);

  final AppDestination currentDestination;
  final String title;
  final Widget body;
  final List<Widget>? actions;

  /// 按壳层断点自动选择显示的响应式动作；与固定 [actions] 并存、追加在后。
  final AppAdaptiveActions? adaptiveActions;

  final Widget? endDrawer;

  /// 是否存在需要优先于路由切换处理的页面本地返回目标（历史选择态、聊天
  /// 显式消息编辑事务）。普通 composer 草稿不属于本地返回目标，不拦返回。
  final bool hasLocalBackTarget;

  /// [hasLocalBackTarget] 为 true 时，系统返回应执行的本地清理回调。
  final VoidCallback? onLocalBack;

  /// 构建唯一的 App Shell 返回层级：系统返回先清本地目标，再回对话页，
  /// 对话根无本地目标时交系统退出。
  ///
  /// 用 PopScope 而非 WillPopScope/Navigator.willPop：Android 预测性返回
  /// 手势只认 PopScope 的 canPop/onPopInvokedWithResult 机制，旧 API 会被
  /// 系统忽略。canPop 只依赖 build 时的同步 UI 状态，不在回调里查询异步
  /// 条件后再决定是否放行路由 pop。
  @override
  Widget build(BuildContext context) {
    final canPop =
        currentDestination == AppDestination.chat && !hasLocalBackTarget;

    return PopScope<void>(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // 页面本地返回目标优先：清理本地状态，路由保持不变。
        if (hasLocalBackTarget) {
          onLocalBack!.call();
          return;
        }
        // 非对话顶层目的地统一退回对话页；对话根没有本地目标时不改写路由，
        // 由系统处理退出。
        if (currentDestination != AppDestination.chat) {
          context.go(AppDestination.chat.path);
        }
      },
      child: _buildShellLayout(context),
    );
  }

  /// 构建自适应页面脚手架，并把路由切换交给 GoRouter。
  Widget _buildShellLayout(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = AppBreakpoints.useCompactShell(constraints.maxWidth);

        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              ...?actions,
              // 响应式动作跟随壳层断点切换紧凑/宽侧分支，排在固定动作之后。
              ...?adaptiveActions?.resolve(constraints.maxWidth),
              // 紧凑布局里才显示抽屉按钮，因为宽屏下侧边导航已经常驻可见。
              if (isCompact && endDrawer != null) _buildDrawerButton(),
            ],
          ),
          endDrawer: isCompact ? endDrawer : null,
          // Android 边缘返回手势与抽屉右缘拖拽抢占同一块屏幕边缘：禁用
          // open drag，把右缘让回系统 Back。抽屉仍可由图标打开，由
          // barrier 点击或系统返回关闭。
          endDrawerEnableOpenDragGesture: false,
          bottomNavigationBar: isCompact
              ? NavigationBar(
                  height: 64,
                  selectedIndex: currentDestination.index,
                  onDestinationSelected: (index) {
                    final destination = AppDestination.values[index];
                    if (destination == currentDestination) {
                      return;
                    }

                    context.go(destination.path);
                  },
                  destinations: [
                    for (final destination in AppDestination.values)
                      NavigationDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(destination.selectedIcon),
                        label: destination.label,
                      ),
                  ],
                )
              : null,
          body: Row(
            children: [
              if (!isCompact) ...[
                _DesktopNavigationRail(currentDestination: currentDestination),
                const VerticalDivider(width: 1),
              ],
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }
}

/// 构建打开 endDrawer 的按钮；必须在紧凑分支且存在 [endDrawer] 时使用。
///
/// 用 Builder 就近取 ScaffoldState，避免依赖 body 内部的 context。
Widget _buildDrawerButton() {
  return Builder(
    builder: (context) {
      return IconButton(
        onPressed: Scaffold.of(context).openEndDrawer,
        tooltip: '打开侧边内容',
        icon: const Icon(Icons.view_sidebar_rounded),
      );
    },
  );
}

/// 供 [AppShellScaffold] 在桌面端使用的导航栏。
class _DesktopNavigationRail extends StatelessWidget {
  const _DesktopNavigationRail({required this.currentDestination});

  final AppDestination currentDestination;

  /// 构建侧边导航栏，并在入口变化时跳转到对应页面。
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return NavigationRail(
      selectedIndex: currentDestination.index,
      onDestinationSelected: (index) {
        final destination = AppDestination.values[index];
        if (destination == currentDestination) {
          return;
        }

        context.go(destination.path);
      },
      labelType: NavigationRailLabelType.all,
      minWidth: 68,
      minExtendedWidth: 220,
      useIndicator: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      destinations: [
        for (final destination in AppDestination.values)
          NavigationRailDestination(
            icon: Icon(destination.icon),
            selectedIcon: Icon(destination.selectedIcon),
            label: Text(destination.label),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_breakpoints.dart';
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
    this.endDrawer,
    super.key,
  });

  final AppDestination currentDestination;
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? endDrawer;

  /// 构建自适应页面脚手架，并把路由切换交给 GoRouter。
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < AppBreakpoints.compact;

        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              ...?actions,
              // 紧凑布局里才显示抽屉按钮，因为宽屏下侧边导航已经常驻可见。
              if (isCompact && endDrawer != null)
                Builder(
                  builder: (context) {
                    return IconButton(
                      onPressed: Scaffold.of(context).openEndDrawer,
                      tooltip: '打开侧边内容',
                      icon: const Icon(Icons.view_sidebar_rounded),
                    );
                  },
                ),
            ],
          ),
          endDrawer: isCompact ? endDrawer : null,
          bottomNavigationBar: isCompact
              ? NavigationBar(
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
      minWidth: 96,
      minExtendedWidth: 220,
      useIndicator: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      leading: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Text('Oh My LLM', style: theme.textTheme.titleLarge),
      ),
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

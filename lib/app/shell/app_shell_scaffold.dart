import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_breakpoints.dart';
import '../navigation/app_destination.dart';

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
                _DesktopNavigationRail(
                  currentDestination: currentDestination,
                ),
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

class _DesktopNavigationRail extends StatelessWidget {
  const _DesktopNavigationRail({
    required this.currentDestination,
  });

  final AppDestination currentDestination;

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
        child: Text(
          'Oh My LLM',
          style: theme.textTheme.titleLarge,
        ),
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

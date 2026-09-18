import 'package:flutter/material.dart';

import '../constants/app_layout_tokens.dart';

/// 页面辅助内容共用的右侧抽屉，窄屏为遮罩关闭保留可点击区域。
class AppSideDrawer extends StatelessWidget {
  const AppSideDrawer({
    required this.title,
    required this.child,
    this.width = AppContentWidths.navigationDrawer,
    super.key,
  });

  final String title;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Drawer(
        width: width.clamp(
          0,
          (constraints.maxWidth - AppInteractionSizes.minimumHitTarget).clamp(
            0,
            double.infinity,
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭侧栏',
                      onPressed: () => Scaffold.of(context).closeEndDrawer(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

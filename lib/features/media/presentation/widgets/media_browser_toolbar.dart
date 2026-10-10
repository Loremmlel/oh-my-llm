import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

import 'media_grid_density_actions.dart';
import 'media_path_bar.dart';
import 'shuffle_appbar_actions.dart';

/// 路径与操作共用一行；窄空间用图标菜单，路径仍可横向滚动。
class MediaBrowserToolbar extends StatelessWidget {
  const MediaBrowserToolbar({
    super.key,
    required this.currentPath,
    required this.onPathSelected,
  });
  final String currentPath;
  final ValueChanged<String> onPathSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = AppBreakpoints.useCompactFormActions(
        constraints.maxWidth,
      );
      final path = MediaPathBar(
        currentPath: currentPath,
        onPathSelected: onPathSelected,
      );
      final actions = Wrap(
        spacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (compact)
            const MediaGridDensityActions.menu()
          else
            const MediaGridDensityActions.labelled(),
          ShuffleAppBarActions(currentDirectoryPath: currentPath),
        ],
      );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(child: path),
            actions,
          ],
        ),
      );
    },
  );
}

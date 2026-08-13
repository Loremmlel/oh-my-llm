import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/constants/app_layout_density.dart';
import 'package:oh_my_llm/features/media/application/media_grid_density_controller.dart';

/// 媒体网格密度切换控件，提供展开与菜单两种形态。
///
/// 展开形态用于宽布局 AppBar（三个并排 IconButton），菜单形态用于窄布局
/// （一个带勾选的 [PopupMenuButton]）。具体展示哪个形态由 AppBar 的
/// [AppAdaptiveActions] 按壳层断点决定；本组件自身不感知窗口宽度，也不做
/// 平台判断（平台绑定留在 app/composition 层）。
enum _MediaGridDensityActionsMode { expanded, menu }

class MediaGridDensityActions extends ConsumerWidget {
  const MediaGridDensityActions.expanded({super.key})
    : _mode = _MediaGridDensityActionsMode.expanded;
  const MediaGridDensityActions.menu({super.key})
    : _mode = _MediaGridDensityActionsMode.menu;

  final _MediaGridDensityActionsMode _mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final density = ref.watch(mediaGridDensityProvider);
    final controller = ref.read(mediaGridDensityProvider.notifier);
    return switch (_mode) {
      _MediaGridDensityActionsMode.expanded => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(
            Icons.density_small,
            '紧凑密度',
            AppLayoutDensity.compact,
            density,
            controller,
          ),
          _button(
            Icons.density_medium,
            '标准密度',
            AppLayoutDensity.standard,
            density,
            controller,
          ),
          _button(
            Icons.density_large,
            '舒适密度',
            AppLayoutDensity.comfortable,
            density,
            controller,
          ),
        ],
      ),
      _MediaGridDensityActionsMode.menu => PopupMenuButton<AppLayoutDensity>(
        tooltip: '显示密度',
        icon: const Icon(Icons.view_module_rounded),
        initialValue: density,
        onSelected: controller.select,
        itemBuilder: (context) => [
          for (final value in AppLayoutDensity.values)
            CheckedPopupMenuItem(
              value: value,
              checked: value == density,
              child: Text(_label(value)),
            ),
        ],
      ),
    };
  }

  /// 单个密度按钮：当前密度带 selected 语义与勾选图标，点击切换密度。
  Widget _button(
    IconData icon,
    String tooltip,
    AppLayoutDensity value,
    AppLayoutDensity current,
    MediaGridDensityController controller,
  ) {
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      isSelected: value == current,
      selectedIcon: const Icon(Icons.check_rounded),
      onPressed: () => controller.select(value),
    );
  }

  /// 菜单项短标签，穷举全部密度。
  String _label(AppLayoutDensity value) => switch (value) {
    AppLayoutDensity.compact => '紧凑',
    AppLayoutDensity.standard => '标准',
    AppLayoutDensity.comfortable => '舒适',
  };
}

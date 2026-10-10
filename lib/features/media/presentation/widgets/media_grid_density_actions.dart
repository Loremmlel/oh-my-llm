import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/constants/app_layout_density.dart';
import 'package:oh_my_llm/features/media/application/media_grid_density_controller.dart';

/// 密度切换复用同一控制器；路径栏用文字菜单直接显示当前值。
enum _MediaGridDensityActionsMode { expanded, menu, labelled }

class MediaGridDensityActions extends ConsumerWidget {
  const MediaGridDensityActions.expanded({super.key})
    : _mode = _MediaGridDensityActionsMode.expanded;
  const MediaGridDensityActions.menu({super.key})
    : _mode = _MediaGridDensityActionsMode.menu;
  const MediaGridDensityActions.labelled({super.key})
    : _mode = _MediaGridDensityActionsMode.labelled;

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
      _MediaGridDensityActionsMode.menu ||
      _MediaGridDensityActionsMode.labelled => Semantics(
        container: true,
        child: PopupMenuButton<AppLayoutDensity>(
          tooltip: '显示密度',
          icon: _mode == _MediaGridDensityActionsMode.menu
              ? const Icon(Icons.view_module_rounded)
              : null,
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
          child: _mode == _MediaGridDensityActionsMode.labelled
              ? Semantics(
                  button: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('显示密度：${_label(density)}'),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                )
              : null,
        ),
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

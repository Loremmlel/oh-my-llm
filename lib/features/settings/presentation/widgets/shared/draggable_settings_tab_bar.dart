import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

import '../../../domain/models/preferences/settings_tab.dart';

/// 设置页可拖拽排序的页签栏。
///
/// 具备以下特性：
/// 1. 宽窄屏自适应：宽屏平铺展示，窄屏横向平滑滚动；
/// 2. 鼠标与触控自适应：
///    - 鼠标：轻点切换标签，按住拖动即时重排；
///    - 触控：轻点切换标签，左右滑动滚动列表，长按拖动重排并带有触觉反馈；
/// 3. 支持提示词下拉分类与总览回调；
/// 4. 监听 [TabController] 状态，保持选中指示条与外部 TabBarView 同步。
class DraggableSettingsTabBar extends StatefulWidget {
  const DraggableSettingsTabBar({
    required this.controller,
    required this.tabs,
    required this.onReorder,
    this.onPromptCategorySelected,
    this.onPromptOverview,
    super.key,
  });

  final TabController controller;
  final List<SettingsTab> tabs;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<int>? onPromptCategorySelected;
  final VoidCallback? onPromptOverview;

  @override
  State<DraggableSettingsTabBar> createState() =>
      _DraggableSettingsTabBarState();
}

class _DraggableSettingsTabBarState extends State<DraggableSettingsTabBar> {
  final ScrollController _scrollController = ScrollController();
  final Map<SettingsTab, GlobalKey> _tabKeys = {};
  int? _lastActiveIndex;

  @override
  void initState() {
    super.initState();
    _lastActiveIndex = widget.controller.index;
    widget.controller.addListener(_onTabControllerChanged);
    _ensureKeys();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToActiveTab();
    });
  }

  @override
  void didUpdateWidget(DraggableSettingsTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTabControllerChanged);
      widget.controller.addListener(_onTabControllerChanged);
      _lastActiveIndex = widget.controller.index;
    }
    _ensureKeys();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTabControllerChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _ensureKeys() {
    for (final tab in widget.tabs) {
      _tabKeys.putIfAbsent(tab, GlobalKey.new);
    }
  }

  void _onTabControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (widget.controller.index != _lastActiveIndex) {
      _lastActiveIndex = widget.controller.index;
      _scrollToActiveTab();
    }
  }

  void _scrollToActiveTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final activeIndex = widget.controller.index;
      if (activeIndex < 0 || activeIndex >= widget.tabs.length) return;
      final activeTab = widget.tabs[activeIndex];
      final key = _tabKeys[activeTab];
      final context = key?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  void _handleTabTap(SettingsTab tab, int index) {
    if (widget.controller.index == index) {
      if (tab == SettingsTab.prompts) {
        widget.onPromptOverview?.call();
      }
      return;
    }
    widget.controller.animateTo(index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outlineVariant.withValues(alpha: 0.5);

    return Container(
      height: 48.0,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor, width: 1.0)),
      ),
      child: ReorderableListView.builder(
        scrollController: _scrollController,
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        itemCount: widget.tabs.length,
        onReorderStart: (_) {
          HapticFeedback.selectionClick();
        },
        proxyDecorator: (child, index, animation) {
          return AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final elevation = Tween<double>(
                begin: 0,
                end: 4,
              ).animate(animation).value;
              return Material(
                elevation: elevation,
                shadowColor: Colors.black38,
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadii.sm),
                child: child,
              );
            },
            child: child,
          );
        },
        onReorderItem: (oldIndex, newIndex) {
          widget.onReorder(oldIndex, newIndex);
        },
        itemBuilder: (context, index) {
          final tab = widget.tabs[index];
          final isSelected = widget.controller.index == index;

          return _AdaptiveReorderableTab(
            key: _tabKeys[tab] ?? ValueKey(tab.key),
            index: index,
            tab: tab,
            isSelected: isSelected,
            onTap: () => _handleTabTap(tab, index),
          );
        },
      ),
    );
  }
}

/// 支持根据输入设备类型（鼠标即时拖动 vs 触控长按拖动）自适应启动拖拽的手势包装。
class AdaptiveReorderableDragListener extends StatelessWidget {
  const AdaptiveReorderableDragListener({
    super.key,
    required this.index,
    required this.child,
    this.enabled = true,
  });

  final int index;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: enabled ? (event) => _startDragging(context, event) : null,
      child: child,
    );
  }

  void _startDragging(BuildContext context, PointerDownEvent event) {
    final gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
    final list = SliverReorderableList.maybeOf(context);
    if (list == null) return;

    final MultiDragGestureRecognizer recognizer;
    final isDesktopPointer =
        event.kind == PointerDeviceKind.mouse ||
        event.kind == PointerDeviceKind.trackpad;
    if (isDesktopPointer) {
      // 鼠标或触控板：按下并移动即触发拖拽重排；未位移松开则由子组件响应点击事件。
      recognizer = ImmediateMultiDragGestureRecognizer(debugOwner: this);
    } else {
      // 触控：长按触发拖拽重排；快速横向滑动为列表正常滚动浏览，轻点为点击切换。
      recognizer = DelayedMultiDragGestureRecognizer(
        delay: const Duration(milliseconds: 300),
        debugOwner: this,
      );
    }

    recognizer.gestureSettings = gestureSettings;
    list.startItemDragReorder(
      index: index,
      event: event,
      recognizer: recognizer,
    );
  }
}

/// 单个自适应拖拽标签项。
class _AdaptiveReorderableTab extends StatelessWidget {
  const _AdaptiveReorderableTab({
    super.key,
    required this.index,
    required this.tab,
    required this.isSelected,
    required this.onTap,
  });

  final int index;
  final SettingsTab tab;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final unselected = theme.colorScheme.onSurfaceVariant;

    final labelStyle =
        (theme.tabBarTheme.labelStyle ??
                theme.textTheme.titleSmall ??
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))
            .copyWith(
              color: isSelected ? primary : unselected,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            );

    return Semantics(
      selected: isSelected,
      button: true,
      label: tab.label,
      child: AdaptiveReorderableDragListener(
        index: index,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadii.sm),
            ),
            onTap: onTap,
            mouseCursor: SystemMouseCursors.click,
            hoverColor: primary.withValues(alpha: 0.08),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48.0),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 12,
                    ),
                    child: Text(tab.label, style: labelStyle),
                  ),
                  if (isSelected)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 3.0,
                        decoration: BoxDecoration(
                          color: primary,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3.0),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

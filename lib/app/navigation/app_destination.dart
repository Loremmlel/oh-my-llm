import 'package:flutter/material.dart';

/// 应用壳支持的顶层入口。
///
/// 每个入口同时提供路由路径和图标，供桌面导航栏和紧凑底部导航共享。
enum AppDestination {
  chat(
    path: '/chat',
    label: '对话',
    icon: Icons.chat_bubble_outline_rounded,
    selectedIcon: Icons.chat_bubble_rounded,
  ),
  history(
    path: '/history',
    label: '历史对话',
    icon: Icons.history_rounded,
    selectedIcon: Icons.history_toggle_off_rounded,
  ),
  favorites(
    path: '/favorites',
    label: '收藏',
    icon: Icons.bookmark_border_rounded,
    selectedIcon: Icons.bookmark_rounded,
  ),
  settings(
    path: '/settings',
    label: '设置',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
  ),
  sync(
    path: '/sync',
    label: '同步',
    icon: Icons.sync_outlined,
    selectedIcon: Icons.sync_rounded,
  );

  const AppDestination({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// 非顶层路由的稳定名称与参数键，供 route builder、导航发起方与测试共享。
///
/// 详情/媒体页面是顶层页面的子页面，不进入 [AppDestination.values]，
/// 否则会错误出现在 NavigationRail/NavigationBar。
abstract final class AppRouteName {
  static const favoriteDetail = 'favoriteDetail';
  static const mediaImage = 'mediaImage';
  static const mediaVideo = 'mediaVideo';
}

abstract final class AppRouteParameter {
  static const favoriteId = 'favoriteId';
  static const mediaPath = 'path';

  /// chat 路由的可序列化会话 ID query 参数键；禁止用 state.extra 传实体。
  static const conversationId = 'conversationId';

  /// history 路由的浏览窗口 query 参数键（页码 / 容量 / 搜索关键词）。
  static const page = 'page';
  static const pageSize = 'pageSize';
  static const q = 'q';
}

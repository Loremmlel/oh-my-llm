import 'package:flutter/material.dart';

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
  settings(
    path: '/settings',
    label: '设置',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
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

import 'package:flutter/material.dart';

import '../../../../core/widgets/app_empty_state.dart';

/// 设置页中的空状态提示组件。
class SettingsEmptyState extends StatelessWidget {
  const SettingsEmptyState({
    required this.icon,
    required this.title,
    required this.description,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: icon,
      title: title,
      description: description,
    );
  }
}

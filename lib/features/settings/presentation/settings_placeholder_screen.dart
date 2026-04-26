import 'package:flutter/material.dart';

import '../../../app/navigation/app_destination.dart';
import '../../../app/shell/app_shell_scaffold.dart';
import '../../../core/widgets/feature_placeholder_view.dart';

class SettingsPlaceholderScreen extends StatelessWidget {
  const SettingsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppShellScaffold(
      currentDestination: AppDestination.settings,
      title: '设置页',
      body: FeaturePlaceholderView(
        title: '设置页',
        description: '设置页已经进入统一导航骨架，接下来会在这里落地模型配置和前置 Prompt 管理。',
        highlights: [
          '模型配置和 Prompt 模板的数据结构已经准备完成。',
          '后续设置会通过本地持久化保存。',
        ],
      ),
    );
  }
}

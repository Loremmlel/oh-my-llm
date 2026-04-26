import 'package:flutter/material.dart';

import '../../../app/navigation/app_destination.dart';
import '../../../app/shell/app_shell_scaffold.dart';
import '../../../core/widgets/feature_placeholder_view.dart';

class HistoryPlaceholderScreen extends StatelessWidget {
  const HistoryPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppShellScaffold(
      currentDestination: AppDestination.history,
      title: '历史对话页',
      body: FeaturePlaceholderView(
        title: '历史对话页',
        description: '历史记录页已经接入应用导航体系，后续会在这里补齐搜索、分组和批量管理能力。',
        highlights: [
          '页面已经拥有独立路由，可直接从导航层切换进入。',
          '后续会复用统一的时间分组规则。',
          '会话点击后会返回主页并定位到目标对话。',
        ],
      ),
    );
  }
}

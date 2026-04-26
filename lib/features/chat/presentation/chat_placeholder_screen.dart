import 'package:flutter/material.dart';

import '../../../app/navigation/app_destination.dart';
import '../../../app/shell/app_shell_scaffold.dart';
import '../../../core/constants/app_breakpoints.dart';
import '../../../core/widgets/feature_placeholder_view.dart';
import '../../../core/widgets/placeholder_panel.dart';

class ChatPlaceholderScreen extends StatelessWidget {
  const ChatPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShellScaffold(
      currentDestination: AppDestination.chat,
      title: '对话页',
      endDrawer: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: _ConversationHistoryPanel(),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showSidePanels =
              constraints.maxWidth >= AppBreakpoints.expanded;

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showSidePanels) ...[
                  const SizedBox(
                    width: 280,
                    child: _ConversationHistoryPanel(),
                  ),
                  const SizedBox(width: 20),
                ],
                const Expanded(
                  child: FeaturePlaceholderView(
                    title: '对话页',
                    description: '主页已经具备三页导航入口和响应式布局骨架，下一步会在这里接入真实的聊天工作区。',
                    highlights: [
                      '桌面端预留了左侧会话列表与右侧消息定位区域。',
                      '移动端会把会话列表折叠到右上角抽屉中。',
                      '后续会在这里接入输入区、消息流和 Markdown 渲染。',
                    ],
                  ),
                ),
                if (showSidePanels) ...[
                  const SizedBox(width: 20),
                  const SizedBox(
                    width: 180,
                    child: _MessageAnchorPanel(),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ConversationHistoryPanel extends StatelessWidget {
  const _ConversationHistoryPanel();

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPanel(
      title: '历史会话面板',
      description: '这里会承载主页左侧的会话列表；在窄屏设备上会折叠到抽屉里。',
      items: [
        '会话列表会按更新时间排序。',
        '会提供最近、一日内、三日内、一周内等分组。',
        '点击后会跳转到当前会话对应位置。',
      ],
    );
  }
}

class _MessageAnchorPanel extends StatelessWidget {
  const _MessageAnchorPanel();

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPanel(
      title: '消息定位条',
      description: '这里会展示用户消息锚点，便于快速跳转到长对话中的指定提问。',
      items: [
        '桌面端会固定在右侧。',
        '锚点默认只展示短标记，悬浮后展示前 10 个字。',
      ],
    );
  }
}

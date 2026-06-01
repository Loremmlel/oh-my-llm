import 'package:flutter/material.dart';

import '../../application/chat_sidebar_controller.dart';

/// 紧凑模式下的侧栏面板，内置功能切换。
///
/// 通过 [SegmentedButton] 在"历史会话"和"预设 Prompt"之间切换，
/// 内容区使用 [IndexedStack] 保持各面板的滚动位置。
class ChatCompactPanel extends StatefulWidget {
  const ChatCompactPanel({
    required this.historyPanel,
    required this.presetPanel,
    super.key,
  });

  /// 历史会话面板（预构建的 [ConversationHistoryPanel]）。
  final Widget historyPanel;

  /// 预设 Prompt 面板（预构建的 [PresetPromptPanel]）。
  final Widget presetPanel;

  @override
  State<ChatCompactPanel> createState() => _ChatCompactPanelState();
}

class _ChatCompactPanelState extends State<ChatCompactPanel> {
  ChatSidebarFunction _activeFunction = ChatSidebarFunction.history;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── 功能切换 ──────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SegmentedButton<ChatSidebarFunction>(
            segments: [
              for (final function in ChatSidebarFunction.values)
                ButtonSegment<ChatSidebarFunction>(
                  value: function,
                  icon: Icon(function.icon, size: 18),
                  label: Text(function.label),
                ),
            ],
            selected: {_activeFunction},
            onSelectionChanged: (selected) {
              setState(() {
                _activeFunction = selected.first;
              });
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        // ── 内容区 ──────────────────────
        Expanded(
          child: IndexedStack(
            index: ChatSidebarFunction.values.indexOf(_activeFunction),
            children: [
              for (final function in ChatSidebarFunction.values)
                _buildPanelFor(function),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPanelFor(ChatSidebarFunction function) {
    return switch (function) {
      ChatSidebarFunction.history => widget.historyPanel,
      ChatSidebarFunction.preset => widget.presetPanel,
    };
  }
}

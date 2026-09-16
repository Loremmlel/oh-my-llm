import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/core/widgets/app_empty_state.dart';

/// 聊天页空状态提示，必要时引导用户去设置服务商与模型。
class EmptyConversationView extends StatelessWidget {
  const EmptyConversationView({required this.hasModels, super.key});

  final bool hasModels;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: AppEmptyState(
                icon: Icons.chat_bubble_outline_rounded,
                iconSize: 48,
                title: hasModels ? '开始一段新对话' : '先准备服务商与模型',
                description: hasModels
                    ? '写下你的问题，或选择一个模板开始。'
                    : '添加服务商和模型后，即可开始对话。',
                action: hasModels
                    ? null
                    : FilledButton.icon(
                        onPressed: () =>
                            context.go(AppDestination.settings.path),
                        icon: const Icon(Icons.settings_rounded),
                        label: const Text('前往设置页'),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

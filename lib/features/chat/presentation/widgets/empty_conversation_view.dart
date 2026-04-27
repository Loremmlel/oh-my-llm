import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/navigation/app_destination.dart';

class EmptyConversationView extends StatelessWidget {
  const EmptyConversationView({required this.hasModels, super.key});

  final bool hasModels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    hasModels ? '开始一段新对话' : '先准备模型配置',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    hasModels
                        ? '输入你的第一条消息后，这里会显示真实的流式回复，同时左侧历史列表和右侧悬浮定位条会一起工作。'
                        : '你还没有配置模型。先去设置页添加一个 OpenAI 兼容模型，聊天页才能真正发起请求。',
                    textAlign: TextAlign.center,
                  ),
                  if (!hasModels) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context.go(AppDestination.settings.path),
                      icon: const Icon(Icons.settings_rounded),
                      label: const Text('前往设置页'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

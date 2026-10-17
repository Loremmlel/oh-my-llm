import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';

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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasModels ? '今天，想聊些什么？' : '先准备服务商与模型',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    hasModels ? '写下你的问题，或选择一个模板开始。' : '添加服务商和模型后，即可开始对话。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/application/preset_prompts_controller.dart';
import '../../../settings/domain/models/preset_prompt.dart';
import 'preset_prompt_message_detail_dialog.dart';

/// 预设 Prompt 单条消息的紧凑卡片。
///
/// 显示消息标题、角色/位置摘要和一个即时生效的启用开关。
/// 点击卡片弹出只读详情弹窗。
class PresetPromptMessageCard extends ConsumerWidget {
  const PresetPromptMessageCard({
    required this.presetId,
    required this.message,
    super.key,
  });

  /// 所属预设的 ID，供 toggle 操作定位。
  final String presetId;

  /// 当前消息（含 enabled 字段）。
  final PromptMessage message;

  IconData get _roleIcon => switch (message.role) {
        PromptMessageRole.system => Icons.smart_toy_outlined,
        PromptMessageRole.user => Icons.person_outline_rounded,
        PromptMessageRole.assistant => Icons.psychology_outlined,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: InkWell(
        onTap: () => _showDetailDialog(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(_roleIcon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${message.role.apiValue} · ${message.placement.label}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: message.enabled,
                onChanged: (_) {
                  ref
                      .read(presetPromptsProvider.notifier)
                      .toggleMessageEnabled(presetId, message.id);
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetailDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => PresetPromptMessageDetailDialog(message: message),
    );
  }
}

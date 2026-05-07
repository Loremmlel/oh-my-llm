import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/checkpoint_request_context.dart';
import '../../../application/chat_sessions_controller.dart';
import '../../../domain/chat_word_counter.dart';
import '../../../domain/models/chat_checkpoint.dart';
import '../../../domain/models/chat_conversation.dart';
import '../../../../settings/application/memory_prompts_controller.dart';
import '../../../../settings/domain/models/llm_model_config.dart';

/// 对话检查点管理弹窗。
class ConversationCheckpointsDialog extends ConsumerStatefulWidget {
  const ConversationCheckpointsDialog({
    required this.selectedModel,
    required this.supportsReasoning,
    super.key,
  });

  final LlmModelConfig? selectedModel;
  final bool supportsReasoning;

  @override
  ConsumerState<ConversationCheckpointsDialog> createState() =>
      _ConversationCheckpointsDialogState();
}

class _ConversationCheckpointsDialogState
    extends ConsumerState<ConversationCheckpointsDialog> {
  String? _selectedMemoryPromptId;
  String? _selectedSourceCheckpointId;
  bool _isCreating = false;

  @override
  Widget build(BuildContext context) {
    final conversation = ref.watch(activeChatConversationProvider);
    final memoryPrompts = ref.watch(memoryPromptsProvider);
    final isBusy = ref.watch(isChatBusyProvider);
    final compatibleCheckpoints = conversation.checkpoints.where((checkpoint) {
      return _isCheckpointCompatible(conversation, checkpoint);
    }).toList(growable: false);
    final selectedMemoryPrompt = memoryPrompts.where((prompt) {
      return prompt.id == _selectedMemoryPromptId;
    }).firstOrNull;
    final selectedSourceCheckpointId =
        compatibleCheckpoints.any((item) => item.id == _selectedSourceCheckpointId)
        ? _selectedSourceCheckpointId
        : compatibleCheckpoints.any(
            (item) => item.id == conversation.selectedCheckpointId,
          )
        ? conversation.selectedCheckpointId
        : null;
    final contextWordCount = conversation.messages.fold<int>(0, (sum, message) {
      return sum + countChatWords(message.content);
    });

    _selectedMemoryPromptId ??= memoryPrompts.firstOrNull?.id;

    return AlertDialog(
      title: const Text('对话检查点'),
      content: SizedBox(
        width: 780,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前上下文字数：$contextWordCount 字（不含前置 Prompt）'),
              const SizedBox(height: 4),
              Text(
                widget.selectedModel == null
                    ? '当前未选择可用模型，暂时只能查看和切换检查点。'
                    : '当前总结模型：${widget.selectedModel!.displayName}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedMemoryPrompt?.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '记忆总结提示词'),
                items: memoryPrompts
                    .map((prompt) {
                      return DropdownMenuItem<String>(
                        value: prompt.id,
                        child: Text(prompt.name),
                      );
                    })
                    .toList(growable: false),
                onChanged: isBusy || memoryPrompts.isEmpty
                    ? null
                    : (value) {
                        setState(() {
                          _selectedMemoryPromptId = value;
                        });
                      },
              ),
              if (memoryPrompts.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '请先去设置页新增记忆总结提示词。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: selectedSourceCheckpointId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '总结来源'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('完整上下文'),
                  ),
                  ...compatibleCheckpoints.map((checkpoint) {
                    final chain = resolveCheckpointChain(
                      checkpoints: conversation.checkpoints,
                      selectedCheckpointId: checkpoint.id,
                    );
                    final suffix = chain.length <= 1
                        ? '根检查点'
                        : '自动携带祖先链 ${chain.length} 条';
                    return DropdownMenuItem<String?>(
                      value: checkpoint.id,
                      child: Text('${checkpoint.title} · $suffix'),
                    );
                  }),
                ],
                onChanged: isBusy
                    ? null
                    : (value) {
                        setState(() {
                          _selectedSourceCheckpointId = value;
                        });
                      },
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isCreating ||
                        isBusy ||
                        widget.selectedModel == null ||
                        selectedMemoryPrompt == null
                    ? null
                    : () async {
                        await _handleCreateCheckpoint(
                          context,
                          conversation,
                          selectedMemoryPromptId: selectedMemoryPrompt.id,
                          sourceCheckpointId: selectedSourceCheckpointId,
                        );
                      },
                icon: const Icon(Icons.summarize_outlined),
                label: Text(_isCreating ? '总结中...' : '创建检查点'),
              ),
              const SizedBox(height: 20),
              Text('当前启用检查点', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              RadioListTile<String?>(
                value: null,
                groupValue: conversation.selectedCheckpointId,
                onChanged: isBusy ? null : (_) => _selectCheckpoint(null),
                title: const Text('不使用检查点'),
                subtitle: const Text('后续对话继续携带完整上下文。'),
                contentPadding: EdgeInsets.zero,
              ),
              if (conversation.checkpoints.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('当前对话还没有检查点。'),
                )
              else
                for (final checkpoint in conversation.checkpoints.reversed)
                  _buildCheckpointTile(
                    context,
                    conversation: conversation,
                    checkpoint: checkpoint,
                    isBusy: isBusy,
                  ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildCheckpointTile(
    BuildContext context, {
    required ChatConversation conversation,
    required ChatCheckpoint checkpoint,
    required bool isBusy,
  }) {
    final compatible = _isCheckpointCompatible(conversation, checkpoint);
    final chain = resolveCheckpointChain(
      checkpoints: conversation.checkpoints,
      selectedCheckpointId: checkpoint.id,
    );
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioListTile<String?>(
              value: checkpoint.id,
              groupValue: conversation.selectedCheckpointId,
              onChanged: compatible && !isBusy
                  ? (_) => _selectCheckpoint(checkpoint.id)
                  : null,
              contentPadding: EdgeInsets.zero,
              title: Text(checkpoint.title),
              subtitle: Text(
                compatible ? _formatCheckpointMeta(checkpoint, chain) : '当前分支不兼容该检查点。',
              ),
            ),
            Text(
              checkpoint.content.trim(),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  bool _isCheckpointCompatible(
    ChatConversation conversation,
    ChatCheckpoint checkpoint,
  ) {
    final requestContext = resolveCheckpointRequestContext(
      checkpoints: conversation.checkpoints,
      selectedCheckpointId: checkpoint.id,
      conversationMessages: conversation.messages,
    );
    return requestContext.hasCheckpoint;
  }

  String _formatCheckpointMeta(
    ChatCheckpoint checkpoint,
    List<ChatCheckpoint> chain,
  ) {
    final date = checkpoint.createdAt.toLocal();
    final memoryPromptName = checkpoint.sourceMemoryPromptName.trim();
    final chainLabel = chain.length <= 1 ? '根检查点' : '祖先链 ${chain.length} 条';
    final promptLabel = memoryPromptName.isEmpty ? '未记录提示词' : memoryPromptName;
    final timeLabel =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return '$chainLabel · $promptLabel · $timeLabel';
  }

  Future<void> _selectCheckpoint(String? checkpointId) async {
    await ref.read(chatSessionsProvider.notifier).selectActiveCheckpoint(checkpointId);
  }

  Future<void> _handleCreateCheckpoint(
    BuildContext context,
    ChatConversation conversation, {
    required String selectedMemoryPromptId,
    required String? sourceCheckpointId,
  }) async {
    final selectedMemoryPrompt = ref.read(memoryPromptsProvider).where((prompt) {
      return prompt.id == selectedMemoryPromptId;
    }).firstOrNull;
    if (selectedMemoryPrompt == null || widget.selectedModel == null) {
      return;
    }

    setState(() {
      _isCreating = true;
    });
    try {
      final checkpoint = await ref.read(chatSessionsProvider.notifier).createCheckpoint(
            modelConfig: widget.selectedModel!,
            memoryPrompt: selectedMemoryPrompt,
            reasoningEnabled:
                widget.supportsReasoning && conversation.reasoningEnabled,
            reasoningEffort: conversation.reasoningEffort,
            sourceCheckpointId: sourceCheckpointId,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedSourceCheckpointId = checkpoint.id;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${checkpoint.title} 已创建')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }
}

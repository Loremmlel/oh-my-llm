import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/date_formatting.dart';
import '../../../../../core/widgets/adaptive_master_detail_layout.dart';
import '../../../../settings/application/memory_prompts_controller.dart';
import '../../../../settings/domain/models/llm_model_config.dart';
import '../../../../settings/domain/models/preset_prompt.dart';
import '../../../application/chat_sessions_controller.dart';
import '../../../application/checkpoint_request_context.dart';
import '../../../domain/chat_word_counter.dart';
import '../../../domain/models/chat_checkpoint.dart';
import '../../../domain/models/chat_conversation.dart';
import '../streaming_markdown_view.dart';
import 'checkpoint_selection_header.dart';
import 'checkpoint_selection_tile.dart';

/// 对话检查点管理弹窗。
class ConversationCheckpointsDialog extends ConsumerStatefulWidget {
  const ConversationCheckpointsDialog({
    required this.selectedModel,
    required this.selectedPresetPrompt,
    required this.supportsReasoning,
    super.key,
  });

  final LlmModelConfig? selectedModel;
  final PresetPrompt? selectedPresetPrompt;
  final bool supportsReasoning;

  @override
  ConsumerState<ConversationCheckpointsDialog> createState() =>
      _ConversationCheckpointsDialogState();
}

class _ConversationCheckpointsDialogState
    extends ConsumerState<ConversationCheckpointsDialog> {
  String? _selectedMemoryPromptId;
  String? _selectedSourceCheckpointId;
  String? _focusedCheckpointId;
  bool _isCreating = false;

  @override
  Widget build(BuildContext context) {
    final conversation = ref.watch(activeChatConversationProvider);
    final memoryPrompts = ref.watch(memoryPromptsProvider);
    final isBusy = ref.watch(isChatBusyProvider);
    final compatibleCheckpoints = conversation.checkpoints
        .where(
          (checkpoint) => _isCheckpointCompatible(conversation, checkpoint),
        )
        .toList(growable: false);
    final selectedMemoryPrompt = memoryPrompts.where((prompt) {
      return prompt.id == _selectedMemoryPromptId;
    }).firstOrNull;
    final selectedSourceCheckpointId =
        compatibleCheckpoints.any(
          (item) => item.id == _selectedSourceCheckpointId,
        )
        ? _selectedSourceCheckpointId
        : compatibleCheckpoints.any(
            (item) => item.id == conversation.selectedCheckpointId,
          )
        ? conversation.selectedCheckpointId
        : null;
    final contextWordCount = conversation.messages.fold<int>(0, (sum, message) {
      return sum + countChatWords(message.content);
    });
    final focusedCheckpointId = _resolveFocusedCheckpointId(conversation);
    final focusedCheckpoint = conversation.checkpoints
        .where((checkpoint) => checkpoint.id == focusedCheckpointId)
        .firstOrNull;

    _selectedMemoryPromptId ??= memoryPrompts.firstOrNull?.id;

    return AlertDialog(
      title: const Text('对话检查点'),
      content: SizedBox(
        width: 920,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前上下文字数：$contextWordCount 字（不含预设 Prompt）'),
              const SizedBox(height: 4),
              Text(
                widget.selectedModel == null
                    ? '当前未选择可用模型，暂时只能查看和切换检查点。'
                    : '当前总结模型：${widget.selectedModel!.displayName}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                widget.selectedPresetPrompt == null
                    ? '当前总结不会附带预设 Prompt。'
                    : '当前总结会附带预设 Prompt：${widget.selectedPresetPrompt!.name}',
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
                onPressed:
                    _isCreating ||
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
              AdaptiveMasterDetailLayout(
                breakpoint: 760,
                masterWidth: 320,
                minHeight: 360,
                compactChild: _buildCompactCheckpointList(
                  context,
                  conversation: conversation,
                  isBusy: isBusy,
                ),
                master: _buildCheckpointMasterPane(
                  context,
                  conversation: conversation,
                  isBusy: isBusy,
                  focusedCheckpointId: focusedCheckpointId,
                ),
                detail: _buildCheckpointDetailPane(
                  context,
                  checkpoint: focusedCheckpoint,
                  conversation: conversation,
                ),
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

  String? _resolveFocusedCheckpointId(ChatConversation conversation) {
    if (_focusedCheckpointId != null &&
        conversation.checkpoints.any(
          (item) => item.id == _focusedCheckpointId,
        )) {
      return _focusedCheckpointId;
    }
    if (conversation.selectedCheckpointId != null &&
        conversation.checkpoints.any(
          (item) => item.id == conversation.selectedCheckpointId,
        )) {
      return conversation.selectedCheckpointId;
    }
    return conversation.checkpoints.isEmpty
        ? null
        : conversation.checkpoints.last.id;
  }

  Widget _buildCompactCheckpointList(
    BuildContext context, {
    required ChatConversation conversation,
    required bool isBusy,
  }) {
    return IgnorePointer(
      ignoring: isBusy,
      child: Opacity(
        opacity: isBusy ? 0.6 : 1,
        child: RadioGroup<String?>(
          groupValue: conversation.selectedCheckpointId,
          onChanged: (value) {
            _selectCheckpoint(value);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const RadioListTile<String?>(
                value: null,
                title: Text('不使用检查点'),
                subtitle: Text('后续对话继续携带完整上下文。'),
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
    );
  }

  Widget _buildCheckpointMasterPane(
    BuildContext context, {
    required ChatConversation conversation,
    required bool isBusy,
    required String? focusedCheckpointId,
  }) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.24,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckpointSelectionHeader(
              isBusy: isBusy,
              usingFullContext: conversation.selectedCheckpointId == null,
              onClearSelection: isBusy ? null : () => _selectCheckpoint(null),
            ),
            const SizedBox(height: 12),
            if (conversation.checkpoints.isEmpty)
              const Expanded(child: Center(child: Text('当前对话还没有检查点。')))
            else
              Expanded(
                child: ListView.separated(
                  itemCount: conversation.checkpoints.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final checkpoint = conversation.checkpoints.reversed
                        .elementAt(index);
                    final compatible = _isCheckpointCompatible(
                      conversation,
                      checkpoint,
                    );
                    final chain = resolveCheckpointChain(
                      checkpoints: conversation.checkpoints,
                      selectedCheckpointId: checkpoint.id,
                    );
                    return CheckpointSelectionTile(
                      checkpoint: checkpoint,
                      meta: compatible
                          ? _formatCheckpointMeta(checkpoint, chain)
                          : '当前分支不兼容该检查点。',
                      selected: checkpoint.id == focusedCheckpointId,
                      applied:
                          checkpoint.id == conversation.selectedCheckpointId,
                      compatible: compatible,
                      onFocus: () {
                        setState(() {
                          _focusedCheckpointId = checkpoint.id;
                        });
                      },
                      onApply: compatible && !isBusy
                          ? () => _selectCheckpoint(checkpoint.id)
                          : null,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckpointDetailPane(
    BuildContext context, {
    required ChatCheckpoint? checkpoint,
    required ChatConversation conversation,
  }) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.18,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: checkpoint == null
          ? Center(
              child: Text(
                '选择一个检查点后，这里会显示完整预览与元信息。',
                style: theme.textTheme.bodyMedium,
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(checkpoint.title, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    _formatCheckpointMeta(
                      checkpoint,
                      resolveCheckpointChain(
                        checkpoints: conversation.checkpoints,
                        selectedCheckpointId: checkpoint.id,
                      ),
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ColoredBox(
                        color: theme.colorScheme.surface,
                        child: SingleChildScrollView(
                          key: ValueKey(
                            'checkpoint-preview-${checkpoint.title}',
                          ),
                          padding: const EdgeInsets.all(12),
                          child: StreamingMarkdownView(
                            content: checkpoint.content.trim(),
                            isStreaming: false,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
    final previewContent = checkpoint.content.trim();
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IgnorePointer(
              ignoring: !compatible || isBusy,
              child: Opacity(
                opacity: compatible && !isBusy ? 1 : 0.6,
                child: RadioListTile<String?>(
                  value: checkpoint.id,
                  contentPadding: EdgeInsets.zero,
                  title: Text(checkpoint.title),
                  subtitle: Text(
                    compatible
                        ? _formatCheckpointMeta(checkpoint, chain)
                        : '当前分支不兼容该检查点。',
                  ),
                ),
              ),
            ),
            if (previewContent.isNotEmpty) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.32,
                  ),
                  child: SizedBox(
                    height: 180,
                    child: SingleChildScrollView(
                      key: ValueKey('checkpoint-preview-${checkpoint.title}'),
                      padding: const EdgeInsets.all(12),
                      child: StreamingMarkdownView(
                        content: previewContent,
                        isStreaming: false,
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
    final timeLabel = formatDateTime(date);
    return '$chainLabel · $promptLabel · $timeLabel';
  }

  void _selectCheckpoint(String? checkpointId) {
    ref
        .read(chatSessionsProvider.notifier)
        .selectActiveCheckpoint(checkpointId);
  }

  Future<void> _handleCreateCheckpoint(
    BuildContext context,
    ChatConversation conversation, {
    required String selectedMemoryPromptId,
    required String? sourceCheckpointId,
  }) async {
    final selectedMemoryPrompt = ref.read(memoryPromptsProvider).where((
      prompt,
    ) {
      return prompt.id == selectedMemoryPromptId;
    }).firstOrNull;
    if (selectedMemoryPrompt == null || widget.selectedModel == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _isCreating = true;
    });
    try {
      final checkpoint = await ref
          .read(chatSessionsProvider.notifier)
          .createCheckpoint(
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
        _focusedCheckpointId = checkpoint.id;
      });
      messenger.showSnackBar(
        SnackBar(content: Text('${checkpoint.title} 已创建')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }
}

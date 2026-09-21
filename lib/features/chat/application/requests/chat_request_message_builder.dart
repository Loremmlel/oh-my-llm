import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/preset_macros/preset_macro_renderer.dart';

import '../../domain/models/chat_checkpoint.dart';
import '../../domain/models/chat_message.dart';
import '../ports/chat_generation_client.dart';
import 'request_message_filter.dart';

export 'request_message_filter.dart';

class ChatPreparedContext {
  ChatPreparedContext(Iterable<ChatRequestMessage> messages, this.preset)
    : messages = List.unmodifiable(messages);

  final List<ChatRequestMessage> messages;
  final PresetRenderResult preset;
  bool get hasErrors => preset.hasErrors;
  String get errorText => preset.diagnostics
      .where((item) => item.isError)
      .map(
        (item) =>
            '${item.title.isEmpty ? '无标题条目' : item.title}：${item.message}',
      )
      .join('\n');

  List<ChatRequestMessage> requireMessages() {
    if (hasErrors) throw ChatGenerationException(errorText);
    return messages;
  }
}

List<ChatRequestMessage> buildRequestMessages({
  required PresetPrompt? presetPrompt,
  required List<ChatMessage> conversationMessages,
  String? latestInputMessageId,
  List<ChatCheckpoint> checkpointChain = const [],
  RequestMessageFilter filter = RequestMessageFilter.passthrough,
}) => prepareChatContext(
  presetPrompt: presetPrompt,
  conversationMessages: conversationMessages,
  latestInputMessageId: latestInputMessageId,
  checkpointChain: checkpointChain,
  filter: filter,
).requireMessages();

/// 发送与预览共享同一求值边界；只有真实会话消息可以提供 lastUserMessage。
ChatPreparedContext prepareChatContext({
  required PresetPrompt? presetPrompt,
  required List<ChatMessage> conversationMessages,
  String? latestInputMessageId,
  List<ChatCheckpoint> checkpointChain = const [],
  RequestMessageFilter filter = RequestMessageFilter.passthrough,
}) {
  final filtered = filter.apply(conversationMessages);
  final latestIndex = filtered.indexWhere(
    (message) =>
        message.id == latestInputMessageId &&
        message.role == ChatMessageRole.user,
  );
  final latestUser = latestInputMessageId == null
      ? filtered.where((m) => m.role == ChatMessageRole.user).lastOrNull
      : latestIndex < 0
      ? null
      : filtered[latestIndex];
  final rendered = renderPresetPrompt(
    presetPrompt,
    lastUserMessage: latestUser?.content ?? '',
  );
  if (rendered.hasErrors) return ChatPreparedContext(const [], rendered);
  final messages = <ChatRequestMessage>[
    ...buildCheckpointMemoryMessages(checkpointChain),
  ];
  void appendPreset(PromptMessagePlacement placement) {
    final entries = rendered.messages
        .where((m) => m.placement == placement)
        .toList();
    final indices = {for (var i = 0; i < entries.length; i++) entries[i].id: i};
    entries.sort((a, b) {
      final order = (a.importInsertionOrder ?? indices[a.id]!).compareTo(
        b.importInsertionOrder ?? indices[b.id]!,
      );
      return order == 0 ? indices[a.id]!.compareTo(indices[b.id]!) : order;
    });
    for (final entry in entries.where((m) => m.content.trim().isNotEmpty)) {
      messages.add(
        ChatRequestMessage(
          role: switch (entry.role) {
            PromptMessageRole.system => ChatMessageRole.system,
            PromptMessageRole.user => ChatMessageRole.user,
            PromptMessageRole.assistant => ChatMessageRole.assistant,
          },
          content: entry.content,
          sourceLabel:
              '预设 · ${entry.title.isEmpty ? '无标题条目' : entry.title} · ${placement.label}',
          sourceId: entry.id,
        ),
      );
    }
  }

  void appendHistory(Iterable<ChatMessage> history) {
    for (final message in history) {
      messages.add(
        ChatRequestMessage(
          role: message.role,
          content: message.content,
          images: message.images,
          sourceId: message.id,
          sourceLabel: message.id == latestInputMessageId ? '当前输入' : '历史消息',
        ),
      );
    }
  }

  final historyEnd = latestIndex < 0 ? filtered.length : latestIndex;
  appendPreset(PromptMessagePlacement.before);
  appendHistory(filtered.take(historyEnd));
  appendPreset(PromptMessagePlacement.beforeLatestInput);
  appendHistory(filtered.skip(historyEnd));
  appendPreset(PromptMessagePlacement.after);
  return ChatPreparedContext(messages, rendered);
}

List<ChatRequestMessage> buildCheckpointMemoryMessages(
  List<ChatCheckpoint> checkpointChain,
) {
  if (checkpointChain.isEmpty) return const [];
  final buffer = StringBuffer(
    '当前对话已启用记忆检查点。以下内容按时间顺序提供，后面的检查点依赖前面的祖先检查点。'
    '请将它们视为用户已确认的重要长期记忆；若与后续原始消息冲突，以后续原始消息为准。',
  );
  for (final checkpoint in checkpointChain) {
    buffer
      ..write('\n\n【${checkpoint.title}】\n')
      ..write(checkpoint.content.trim());
  }
  return [
    ChatRequestMessage(
      role: ChatMessageRole.system,
      content: buffer.toString().trim(),
      sourceLabel: '检查点记忆',
    ),
  ];
}

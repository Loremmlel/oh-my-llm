import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';

import '../../domain/models/chat_conversation.dart';
import '../../domain/models/chat_image_attachment.dart';
import '../../domain/models/chat_message.dart';
import 'chat_request_message_builder.dart';
import 'checkpoint_request_context.dart';

/// 草稿只形成临时请求视图，不写入消息树或改变当前分支选择。
ChatPreparedContext previewChatContext({
  required ChatConversation conversation,
  required PresetPrompt? presetPrompt,
  String body = '',
  List<ChatImageAttachment> images = const [],
  String? editingMessageId,
}) {
  var history = conversation.messages;
  if (editingMessageId != null) {
    final index = history.indexWhere(
      (m) => m.id == editingMessageId && m.role == ChatMessageRole.user,
    );
    if (index < 0) throw StateError('编辑的消息已不在当前分支');
    history = history.take(index).toList();
  }
  final hasInput = body.trim().isNotEmpty || images.isNotEmpty;
  final input = hasInput
      ? ChatMessage(
          id: '__context_preview_input__',
          role: ChatMessageRole.user,
          content: body.trim(),
          images: List.unmodifiable(images),
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        )
      : null;
  final context = resolveCheckpointRequestContext(
    checkpoints: conversation.checkpoints,
    selectedCheckpointId: conversation.selectedCheckpointId,
    conversationMessages: [...history, ?input],
  );
  return prepareChatContext(
    presetPrompt: presetPrompt,
    conversationMessages: context.tailMessages,
    latestInputMessageId: input?.id,
    checkpointChain: context.checkpointChain,
    filter: ExcludeByIdMessageFilter(conversation.excludedMessageIds.toSet()),
  );
}

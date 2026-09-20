import '../../domain/models/chat_conversation.dart';
import '../../domain/models/chat_image_attachment.dart';
import 'checkpoint_request_context.dart';

const unsupportedChatImageInputMessage =
    '当前模型未开启图像输入。请切换模型、开启模型的图像能力，或移除／排除图片。';

/// 与实际请求共用检查点裁剪；编辑时只检查新分支之前的历史和替换后的草稿。
bool isChatImageInputBlocked({
  required bool supportsImageInput,
  required ChatConversation conversation,
  required List<ChatImageAttachment> draftImages,
  String? editingMessageId,
}) {
  if (supportsImageInput) return false;
  if (draftImages.isNotEmpty) return true;
  final history = conversation.messages;
  final editIndex = editingMessageId == null
      ? -1
      : history.indexWhere((message) => message.id == editingMessageId);
  final context = resolveCheckpointRequestContext(
    checkpoints: conversation.checkpoints,
    selectedCheckpointId: conversation.selectedCheckpointId,
    conversationMessages: editIndex < 0
        ? history
        : history.take(editIndex).toList(),
  );
  return context.tailMessages.any(
    (message) =>
        message.images.isNotEmpty &&
        !conversation.isMessageExcluded(message.id),
  );
}

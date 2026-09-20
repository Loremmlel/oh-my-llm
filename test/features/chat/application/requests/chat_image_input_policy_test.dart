import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/chat/application/requests/chat_image_input_policy.dart';
import 'package:oh_my_llm/features/chat/application/requests/checkpoint_request_context.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_checkpoint.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/memory_prompt.dart';

import '../../../../helpers/chat/test_chat_images.dart';

void main() {
  final now = DateTime(2026);
  final message = ChatMessage(
    id: 'image',
    role: ChatMessageRole.user,
    content: '',
    createdAt: now,
    images: [testChatImage],
  );
  final conversation = ChatConversation(
    id: 'c',
    createdAt: now,
    updatedAt: now,
    messageNodes: [message],
  );
  bool blocked(ChatConversation value, {String? edit}) =>
      isChatImageInputBlocked(
        supportsImageInput: false,
        conversation: value,
        draftImages: const [],
        editingMessageId: edit,
      );

  test('草稿与历史图片均拦截，排除消息和移除编辑图片后可发送', () {
    expect(blocked(conversation), isTrue);
    expect(
      blocked(conversation.copyWith(excludedMessageIds: ['image'])),
      isFalse,
    );
    expect(blocked(conversation, edit: 'image'), isFalse);
    expect(
      isChatImageInputBlocked(
        supportsImageInput: false,
        conversation: conversation,
        draftImages: [testChatImage],
        editingMessageId: 'image',
      ),
      isTrue,
    );
    expect(
      isChatImageInputBlocked(
        supportsImageInput: true,
        conversation: conversation,
        draftImages: [testChatImage],
      ),
      isFalse,
    );
  });

  test('有效检查点覆盖的图片不拦截，失效检查点恢复历史图像检查', () {
    final checkpoint = ChatCheckpoint(
      id: 'cp',
      title: '摘要',
      content: '图片摘要',
      createdAt: now,
      coveredUntilMessageId: 'image',
    );
    expect(
      blocked(
        conversation.copyWith(
          checkpoints: [checkpoint],
          selectedCheckpointId: 'cp',
        ),
      ),
      isFalse,
    );
    expect(
      blocked(
        conversation.copyWith(
          checkpoints: [checkpoint.copyWith(coveredUntilMessageId: 'missing')],
          selectedCheckpointId: 'cp',
        ),
      ),
      isTrue,
    );
  });

  test('检查点总结保留源图片，随后由生成适配器统一检查模型能力', () {
    final messages = buildCheckpointSummaryMessages(
      memoryPrompt: MemoryPrompt(
        id: 'p',
        name: '总结',
        content: '总结',
        updatedAt: now,
      ),
      conversationMessages: [message],
    );
    expect(messages.expand((m) => m.images), [testChatImage]);
  });
}

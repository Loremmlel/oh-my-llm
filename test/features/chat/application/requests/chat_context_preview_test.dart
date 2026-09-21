import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/chat/application/requests/chat_context_preview.dart';
import 'package:oh_my_llm/features/chat/application/requests/chat_request_message_builder.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_checkpoint.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';

void main() {
  final now = DateTime(2026);
  ChatMessage message(
    String id,
    String? parent,
    ChatMessageRole role,
    String content,
  ) => ChatMessage(
    id: id,
    parentId: parent,
    role: role,
    content: content,
    createdAt: now,
  );
  final conversation = ChatConversation(
    id: 'c',
    createdAt: now,
    updatedAt: now,
    messageNodes: [
      message('u1', null, ChatMessageRole.user, '旧输入'),
      message('a1', 'u1', ChatMessageRole.assistant, '旧回复'),
      message('u2', 'a1', ChatMessageRole.user, '原输入'),
      message('a2', 'u2', ChatMessageRole.assistant, '原分支后续'),
    ],
  );
  final preset = PresetPrompt(
    id: 'p',
    name: '写作',
    updatedAt: now,
    syntax: PresetPromptSyntax.sillyTavernSubsetV1,
    messages: [
      const PromptMessage(
        id: 'assignment',
        role: PromptMessageRole.user,
        content: '{{setvar::x::要求}}',
        placement: PromptMessagePlacement.after,
      ),
      const PromptMessage(
        id: 'before',
        role: PromptMessageRole.system,
        content: '{{getvar::x}}',
        placement: PromptMessagePlacement.beforeLatestInput,
      ),
      const PromptMessage(
        id: 'after',
        role: PromptMessageRole.system,
        content: '<input>{{lastUserMessage}}</input>',
        placement: PromptMessagePlacement.after,
      ),
    ],
  );

  test('编辑预览使用新输入和祖先路径，原分支与赋值条目不会进入请求', () {
    final result = previewChatContext(
      conversation: conversation,
      presetPrompt: preset,
      body: '编辑内容',
      editingMessageId: 'u2',
    );
    expect(result.messages.map((m) => m.content), [
      '旧输入',
      '旧回复',
      '要求',
      '编辑内容',
      '<input>编辑内容</input>',
    ]);
    expect(conversation.messages.last.content, '原分支后续');
  });
  test('检查点裁剪和排除同时作用于预览与最新用户宏', () {
    final checkpoint = ChatCheckpoint(
      id: 'checkpoint',
      title: '记忆',
      content: '摘要',
      createdAt: now,
      coveredUntilMessageId: 'u2',
    );
    final compacted = conversation.copyWith(
      checkpoints: [checkpoint],
      selectedCheckpointId: checkpoint.id,
      excludedMessageIds: ['a2'],
    );
    final result = previewChatContext(
      conversation: compacted,
      presetPrompt: preset,
    );
    expect(result.messages.map((m) => m.content).skip(1), [
      '要求',
      '<input></input>',
    ]);
    expect(result.messages.first.sourceLabel, '检查点记忆');
  });
  test('最新输入被排除时宏不回读更早的用户文本', () {
    final result = prepareChatContext(
      presetPrompt: preset,
      conversationMessages: conversation.messages.take(3).toList(),
      latestInputMessageId: 'u2',
      filter: const ExcludeByIdMessageFilter({'u2'}),
    );
    expect(result.messages.last.content, '<input></input>');
  });
  test('解析失败不暴露可发送的半截消息', () {
    final invalid = preset.copyWith(
      messages: [
        const PromptMessage(
          id: 'broken',
          title: '坏条目',
          role: PromptMessageRole.system,
          content: '{{setvar::x}}',
        ),
      ],
    );
    final preview = previewChatContext(
      conversation: conversation,
      presetPrompt: invalid,
      body: '保留草稿',
    );
    expect(preview.hasErrors, isTrue);
    expect(preview.messages, isEmpty);
    expect(preview.errorText, contains('坏条目'));
    expect(preview.requireMessages, throwsA(isA<Exception>()));
  });
}

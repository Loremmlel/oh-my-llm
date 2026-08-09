import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/chat_request_message_builder.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_checkpoint.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/preset_prompt.dart';

void main() {
  ChatMessage message(String id, ChatMessageRole role, String content) =>
      ChatMessage(
        id: id,
        role: role,
        content: content,
        createdAt: DateTime(2026),
      );

  PromptMessage promptMessage(
    String id,
    PromptMessageRole role,
    String content, {
    PromptMessagePlacement placement = PromptMessagePlacement.before,
    bool enabled = true,
  }) => PromptMessage(
    id: id,
    role: role,
    content: content,
    placement: placement,
    enabled: enabled,
  );

  PresetPrompt template(List<PromptMessage> messages) => PresetPrompt(
    id: 'template',
    name: '测试模板',
    messages: messages,
    updatedAt: DateTime(2026),
  );

  test('无模板时按原角色和内容透传会话消息，空输入仍为空', () {
    final result = buildRequestMessages(
      presetPrompt: null,
      conversationMessages: [
        message('u1', ChatMessageRole.user, '你好\n！'),
        message('a1', ChatMessageRole.assistant, '你好！'),
      ],
    );

    expect(result.map((item) => item.role), [
      ChatMessageRole.user,
      ChatMessageRole.assistant,
    ]);
    expect(result.map((item) => item.content), ['你好\n！', '你好！']);
    expect(
      buildRequestMessages(presetPrompt: null, conversationMessages: const []),
      isEmpty,
    );
  });

  test('三种模板位置保持各自顺序并正确转换全部角色', () {
    final result = buildRequestMessages(
      presetPrompt: template([
        promptMessage('before-user', PromptMessageRole.user, '前置用户'),
        promptMessage(
          'latest-system',
          PromptMessageRole.system,
          '最新输入前系统',
          placement: PromptMessagePlacement.beforeLatestInput,
        ),
        promptMessage(
          'after-assistant',
          PromptMessageRole.assistant,
          '后置助手',
          placement: PromptMessagePlacement.after,
        ),
        promptMessage('before-assistant', PromptMessageRole.assistant, '前置助手'),
        promptMessage(
          'latest-user',
          PromptMessageRole.user,
          '最新输入前用户',
          placement: PromptMessagePlacement.beforeLatestInput,
        ),
      ]),
      conversationMessages: [message('u1', ChatMessageRole.user, '真实问题')],
    );

    expect(result.map((item) => item.content), [
      '前置用户',
      '前置助手',
      '真实问题',
      '最新输入前系统',
      '最新输入前用户',
      '后置助手',
    ]);
    expect(result.map((item) => item.role), [
      ChatMessageRole.user,
      ChatMessageRole.assistant,
      ChatMessageRole.user,
      ChatMessageRole.system,
      ChatMessageRole.user,
      ChatMessageRole.assistant,
    ]);
  });

  test('禁用或纯空白模板消息不会进入请求', () {
    final result = buildRequestMessages(
      presetPrompt: template([
        promptMessage(
          'disabled',
          PromptMessageRole.system,
          '禁用',
          enabled: false,
        ),
        promptMessage('blank', PromptMessageRole.system, '   '),
        promptMessage('enabled', PromptMessageRole.system, '保留'),
      ]),
      conversationMessages: const [],
    );

    expect(result.map((item) => item.content), ['保留']);
  });

  test('filter 只过滤会话消息，不过滤模板消息', () {
    final result = buildRequestMessages(
      presetPrompt: template([
        promptMessage('template', PromptMessageRole.system, '模板前置'),
      ]),
      filter: const ExcludeByIdMessageFilter({'a1'}),
      conversationMessages: [
        message('u1', ChatMessageRole.user, '真实问题'),
        message('a1', ChatMessageRole.assistant, '被排除回复'),
      ],
    );

    expect(result.map((item) => item.content), ['模板前置', '真实问题']);
  });

  test('检查点记忆在模板和会话之前，且不受会话 filter 影响', () {
    final result = buildRequestMessages(
      presetPrompt: template([
        promptMessage('template', PromptMessageRole.system, '模板前置'),
      ]),
      checkpointChain: [
        ChatCheckpoint(
          id: 'checkpoint',
          title: '检查点 1',
          content: '已确认记忆',
          createdAt: DateTime(2026),
        ),
      ],
      filter: const ExcludeByIdMessageFilter({'a1'}),
      conversationMessages: [
        message('u1', ChatMessageRole.user, '新的问题'),
        message('a1', ChatMessageRole.assistant, '旧回复'),
      ],
    );

    expect(result.map((item) => item.role), [
      ChatMessageRole.system,
      ChatMessageRole.system,
      ChatMessageRole.user,
    ]);
    expect(result.first.content, contains('检查点 1'));
    expect(result.map((item) => item.content).skip(1), ['模板前置', '新的问题']);
  });
}

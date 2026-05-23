import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/chat_request_message_builder.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_checkpoint.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompt_template.dart';

void main() {
  // ── 辅助函数 ─────────────────────────────────────────────────────────────

  ChatMessage buildUserMessage(String content) => ChatMessage(
    id: 'u1',
    role: ChatMessageRole.user,
    content: content,
    createdAt: DateTime(2026),
  );

  ChatMessage buildAssistantMessage(String content) => ChatMessage(
    id: 'a1',
    role: ChatMessageRole.assistant,
    content: content,
    createdAt: DateTime(2026),
  );

  PromptTemplate buildTemplate({
    String systemPrompt = '',
    List<PromptMessage> messages = const [],
  }) {
    final effectiveMessages = systemPrompt.trim().isNotEmpty
        ? <PromptMessage>[
            PromptMessage(
              id: '_legacy-system-message',
              role: PromptMessageRole.system,
              title: defaultSystemPromptTitle,
              content: systemPrompt.trim(),
            ),
            ...messages,
          ]
        : messages;
    return PromptTemplate(
      id: 'tpl-1',
      name: '测试模板',
      messages: effectiveMessages,
      updatedAt: DateTime(2026),
    );
  }

  PromptMessage buildTemplateMessage(
    PromptMessageRole role,
    String content, {
    PromptMessagePlacement placement = PromptMessagePlacement.before,
  }) => PromptMessage(
    id: 'pm1',
    role: role,
    content: content,
    placement: placement,
  );

  // ── 无模板 ────────────────────────────────────────────────────────────────

  group('无模板（promptTemplate == null）', () {
    test('透传会话消息，并在没有会话消息时返回空列表', () {
      final result = buildRequestMessages(
        promptTemplate: null,
        conversationMessages: [
          buildUserMessage('你好'),
          buildAssistantMessage('你好！'),
        ],
      );

      expect(result, hasLength(2));
      expect(result[0].role, ChatMessageRole.user);
      expect(result[1].role, ChatMessageRole.assistant);
      expect(
        buildRequestMessages(
          promptTemplate: null,
          conversationMessages: const [],
        ),
        isEmpty,
      );
    });
  });

  // ── 有模板：system prompt ─────────────────────────────────────────────────

  group('模板含 systemPrompt', () {
    test('非空 systemPrompt 会在首位插入裁剪后的 system 消息', () {
      final result = buildRequestMessages(
        promptTemplate: buildTemplate(systemPrompt: '  你是一名助手  '),
        conversationMessages: [buildUserMessage('问题')],
      );

      expect(result[0].role, ChatMessageRole.system);
      expect(result[0].content, '你是一名助手');
      expect(result, hasLength(2));
    });

    test('纯空白 systemPrompt 不插入 system 消息', () {
      final result = buildRequestMessages(
        promptTemplate: buildTemplate(systemPrompt: '   '),
        conversationMessages: [buildUserMessage('问题')],
      );

      expect(result.any((m) => m.role == ChatMessageRole.system), isFalse);
    });
  });

  // ── 有模板：template messages ─────────────────────────────────────────────

  group('模板含 messages', () {
    test('模板消息排在会话消息前面', () {
      final result = buildRequestMessages(
        promptTemplate: buildTemplate(
          messages: [
            buildTemplateMessage(PromptMessageRole.user, '示例问题'),
            buildTemplateMessage(PromptMessageRole.assistant, '示例回答'),
          ],
        ),
        conversationMessages: [buildUserMessage('真实问题')],
      );

      expect(result[0].content, '示例问题');
      expect(result[1].content, '示例回答');
      expect(result[2].content, '真实问题');
    });

    test('模板 user 消息转换为 ChatMessageRole.user', () {
      final result = buildRequestMessages(
        promptTemplate: buildTemplate(
          messages: [buildTemplateMessage(PromptMessageRole.user, 'u')],
        ),
        conversationMessages: const [],
      );

      expect(result.single.role, ChatMessageRole.user);
    });

    test('模板 assistant 消息转换为 ChatMessageRole.assistant', () {
      final result = buildRequestMessages(
        promptTemplate: buildTemplate(
          messages: [buildTemplateMessage(PromptMessageRole.assistant, 'a')],
        ),
        conversationMessages: const [],
      );

      expect(result.single.role, ChatMessageRole.assistant);
    });

    test('模板 system 消息转换为 ChatMessageRole.system，并支持多条', () {
      final result = buildRequestMessages(
        promptTemplate: buildTemplate(
          messages: [
            buildTemplateMessage(PromptMessageRole.system, '系统前置'),
            buildTemplateMessage(
              PromptMessageRole.system,
              '系统后置',
              placement: PromptMessagePlacement.after,
            ),
          ],
        ),
        conversationMessages: [buildUserMessage('真实问题')],
      );

      expect(result.map((message) => message.role).toList(), [
        ChatMessageRole.system,
        ChatMessageRole.user,
        ChatMessageRole.system,
      ]);
      expect(result.map((message) => message.content).toList(), [
        '系统前置',
        '真实问题',
        '系统后置',
      ]);
    });

    test('after 模板消息排在会话消息后面', () {
      final result = buildRequestMessages(
        promptTemplate: buildTemplate(
          messages: [
            buildTemplateMessage(
              PromptMessageRole.assistant,
              '后置提示',
              placement: PromptMessagePlacement.after,
            ),
          ],
        ),
        conversationMessages: [buildUserMessage('真实问题')],
      );

      expect(result, hasLength(2));
      expect(result[0].content, '真实问题');
      expect(result[1].content, '后置提示');
    });

    test('filter 只会跳过被排除的会话消息', () {
      final result = buildRequestMessages(
        promptTemplate: buildTemplate(
          systemPrompt: '系统指令',
          messages: [
            buildTemplateMessage(PromptMessageRole.user, '模板前置'),
            buildTemplateMessage(
              PromptMessageRole.assistant,
              '模板后置',
              placement: PromptMessagePlacement.after,
            ),
          ],
        ),
        filter: const ExcludeByIdMessageFilter({'a1'}),
        conversationMessages: [
          buildUserMessage('真实问题'),
          buildAssistantMessage('不应继续发送的旧回复'),
        ],
      );

      expect(result.map((message) => message.content).toList(growable: false), [
        '系统指令',
        '模板前置',
        '真实问题',
        '模板后置',
      ]);
    });

    test('before 和 after 混用时，顺序为 before -> 会话 -> after', () {
      final result = buildRequestMessages(
        promptTemplate: buildTemplate(
          messages: [
            buildTemplateMessage(PromptMessageRole.user, '前置-1'),
            buildTemplateMessage(
              PromptMessageRole.assistant,
              '后置-1',
              placement: PromptMessagePlacement.after,
            ),
            buildTemplateMessage(PromptMessageRole.assistant, '前置-2'),
          ],
        ),
        conversationMessages: [buildUserMessage('真实问题')],
      );

      expect(result.map((m) => m.content).toList(), [
        '前置-1',
        '前置-2',
        '真实问题',
        '后置-1',
      ]);
    });
  });

  // ── 完整组合 ──────────────────────────────────────────────────────────────

  group('完整组合：system + template messages + 会话消息', () {
    test('顺序为 system → 模板消息 → 会话消息', () {
      final result = buildRequestMessages(
        promptTemplate: buildTemplate(
          systemPrompt: '系统指令',
          messages: [
            buildTemplateMessage(PromptMessageRole.user, '示例用户'),
            buildTemplateMessage(PromptMessageRole.assistant, '示例助手'),
          ],
        ),
        conversationMessages: [
          buildUserMessage('真实用户'),
          buildAssistantMessage('真实助手'),
        ],
      );

      expect(result, hasLength(5));
      expect(result[0].role, ChatMessageRole.system);
      expect(result[0].content, '系统指令');
      expect(result[1].content, '示例用户');
      expect(result[2].content, '示例助手');
      expect(result[3].content, '真实用户');
      expect(result[4].content, '真实助手');
    });

    test('会话消息的 content 原样透传', () {
      const longContent = '这是一段比较长的内容，包含换行\n和特殊字符！@#\$%^';
      final result = buildRequestMessages(
        promptTemplate: null,
        conversationMessages: [
          ChatMessage(
            id: 'u',
            role: ChatMessageRole.user,
            content: longContent,
            createdAt: DateTime(2026),
          ),
        ],
      );

      expect(result.single.content, longContent);
    });
  });

  test('启用检查点时会在会话消息前插入检查点 system 消息', () {
    final result = buildRequestMessages(
      promptTemplate: null,
      checkpointChain: [
        ChatCheckpoint(
          id: 'cp-1',
          title: '检查点 1',
          content: '已确认的长期记忆',
          createdAt: DateTime(2026),
        ),
      ],
      conversationMessages: [buildUserMessage('新的问题')],
    );

    expect(result, hasLength(2));
    expect(result.first.role, ChatMessageRole.system);
    expect(result.first.content, contains('检查点 1'));
    expect(result.last.content, '新的问题');
  });

  test('filter 不影响检查点 system 消息，只过滤会话消息', () {
    final result = buildRequestMessages(
      promptTemplate: null,
      checkpointChain: [
        ChatCheckpoint(
          id: 'cp-1',
          title: '检查点 1',
          content: '已确认记忆',
          createdAt: DateTime(2026),
        ),
      ],
      filter: const ExcludeByIdMessageFilter({'a1'}),
      conversationMessages: [
        buildUserMessage('新的问题'),
        buildAssistantMessage('旧回复'),
      ],
    );

    expect(result, hasLength(2));
    expect(result.first.role, ChatMessageRole.system);
    expect(result.last.content, '新的问题');
  });
}

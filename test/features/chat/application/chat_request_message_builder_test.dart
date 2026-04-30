import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/chat_request_message_builder.dart';
import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompt_template.dart';

void main() {
  // ── 辅助函数 ─────────────────────────────────────────────────────────────

  ChatMessage _userMsg(String content) => ChatMessage(
    id: 'u1',
    role: ChatMessageRole.user,
    content: content,
    createdAt: DateTime(2026),
  );

  ChatMessage _assistantMsg(String content) => ChatMessage(
    id: 'a1',
    role: ChatMessageRole.assistant,
    content: content,
    createdAt: DateTime(2026),
  );

  PromptTemplate _template({
    String systemPrompt = '',
    List<PromptMessage> messages = const [],
  }) {
    return PromptTemplate(
      id: 'tpl-1',
      name: '测试模板',
      systemPrompt: systemPrompt,
      messages: messages,
      updatedAt: DateTime(2026),
    );
  }

  PromptMessage _tplMsg(
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
    test('只返回会话消息', () {
      final result = buildRequestMessages(
        promptTemplate: null,
        conversationMessages: [_userMsg('你好'), _assistantMsg('你好！')],
      );

      expect(result, hasLength(2));
      expect(result[0].role, ChatMessageRole.user);
      expect(result[1].role, ChatMessageRole.assistant);
    });

    test('会话消息为空时返回空列表', () {
      final result = buildRequestMessages(
        promptTemplate: null,
        conversationMessages: const [],
      );

      expect(result, isEmpty);
    });

    test('返回不可变列表', () {
      final result = buildRequestMessages(
        promptTemplate: null,
        conversationMessages: [_userMsg('test')],
      );

      expect(
        () => result.add(
          const ChatCompletionRequestMessage(
            role: ChatMessageRole.user,
            content: 'x',
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });

  // ── 有模板：system prompt ─────────────────────────────────────────────────

  group('模板含 systemPrompt', () {
    test('非空 systemPrompt 作为第一条 system 消息插入', () {
      final result = buildRequestMessages(
        promptTemplate: _template(systemPrompt: '你是一名助手'),
        conversationMessages: [_userMsg('问题')],
      );

      expect(result[0].role, ChatMessageRole.system);
      expect(result[0].content, '你是一名助手');
      expect(result, hasLength(2));
    });

    test('纯空白 systemPrompt 不插入 system 消息', () {
      final result = buildRequestMessages(
        promptTemplate: _template(systemPrompt: '   '),
        conversationMessages: [_userMsg('问题')],
      );

      expect(result.any((m) => m.role == ChatMessageRole.system), isFalse);
    });

    test('systemPrompt 首尾空白被 trim', () {
      final result = buildRequestMessages(
        promptTemplate: _template(systemPrompt: '  你是助手  '),
        conversationMessages: [_userMsg('问题')],
      );

      expect(result[0].content, '你是助手');
    });
  });

  // ── 有模板：template messages ─────────────────────────────────────────────

  group('模板含 messages', () {
    test('模板消息排在会话消息前面', () {
      final result = buildRequestMessages(
        promptTemplate: _template(
          messages: [
            _tplMsg(PromptMessageRole.user, '示例问题'),
            _tplMsg(PromptMessageRole.assistant, '示例回答'),
          ],
        ),
        conversationMessages: [_userMsg('真实问题')],
      );

      expect(result[0].content, '示例问题');
      expect(result[1].content, '示例回答');
      expect(result[2].content, '真实问题');
    });

    test('模板 user 消息转换为 ChatMessageRole.user', () {
      final result = buildRequestMessages(
        promptTemplate: _template(
          messages: [_tplMsg(PromptMessageRole.user, 'u')],
        ),
        conversationMessages: const [],
      );

      expect(result.single.role, ChatMessageRole.user);
    });

    test('模板 assistant 消息转换为 ChatMessageRole.assistant', () {
      final result = buildRequestMessages(
        promptTemplate: _template(
          messages: [_tplMsg(PromptMessageRole.assistant, 'a')],
        ),
        conversationMessages: const [],
      );

      expect(result.single.role, ChatMessageRole.assistant);
    });

    test('模板消息列表为空时不增加额外条目', () {
      final result = buildRequestMessages(
        promptTemplate: _template(),
        conversationMessages: [_userMsg('问题')],
      );

      // 没有 system（空），没有模板消息，只有一条会话消息。
      expect(result, hasLength(1));
      expect(result.single.content, '问题');
    });

    test('after 模板消息排在会话消息后面', () {
      final result = buildRequestMessages(
        promptTemplate: _template(
          messages: [
            _tplMsg(
              PromptMessageRole.assistant,
              '后置提示',
              placement: PromptMessagePlacement.after,
            ),
          ],
        ),
        conversationMessages: [_userMsg('真实问题')],
      );

      expect(result, hasLength(2));
      expect(result[0].content, '真实问题');
      expect(result[1].content, '后置提示');
    });

    test('before 和 after 混用时，顺序为 before -> 会话 -> after', () {
      final result = buildRequestMessages(
        promptTemplate: _template(
          messages: [
            _tplMsg(PromptMessageRole.user, '前置-1'),
            _tplMsg(
              PromptMessageRole.assistant,
              '后置-1',
              placement: PromptMessagePlacement.after,
            ),
            _tplMsg(PromptMessageRole.assistant, '前置-2'),
          ],
        ),
        conversationMessages: [_userMsg('真实问题')],
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
        promptTemplate: _template(
          systemPrompt: '系统指令',
          messages: [
            _tplMsg(PromptMessageRole.user, '示例用户'),
            _tplMsg(PromptMessageRole.assistant, '示例助手'),
          ],
        ),
        conversationMessages: [_userMsg('真实用户'), _assistantMsg('真实助手')],
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

  // ── 返回类型 ──────────────────────────────────────────────────────────────

  group('返回类型约束', () {
    test('返回的每条消息均为 ChatCompletionRequestMessage', () {
      final result = buildRequestMessages(
        promptTemplate: _template(systemPrompt: 'sys'),
        conversationMessages: [_userMsg('hi')],
      );

      expect(result, everyElement(isA<ChatCompletionRequestMessage>()));
    });
  });
}

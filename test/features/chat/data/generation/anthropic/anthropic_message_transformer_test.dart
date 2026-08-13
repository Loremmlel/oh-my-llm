import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/data/generation/anthropic/anthropic_message_transformer.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

void main() {
  ChatRequestMessage message(ChatMessageRole role, String content) {
    return ChatRequestMessage(role: role, content: content);
  }

  group('leading System → 顶层 system', () {
    test('连续前导 System 全部并入，单换行连接', () {
      final result = transformAnthropicMessages([
        message(ChatMessageRole.system, '系统一'),
        message(ChatMessageRole.system, '系统二'),
        message(ChatMessageRole.user, '你好'),
      ]);
      expect(result.system, '系统一\n系统二');
      expect(result.messages, const [
        AnthropicTransformedMessage(role: 'user', content: '你好'),
      ]);
    });

    test('无 leading System → system 为 null', () {
      final result = transformAnthropicMessages([
        message(ChatMessageRole.user, '你好'),
        message(ChatMessageRole.assistant, '回复'),
      ]);
      expect(result.system, isNull);
      expect(result.messages, const [
        AnthropicTransformedMessage(role: 'user', content: '你好'),
        AnthropicTransformedMessage(role: 'assistant', content: '回复'),
      ]);
    });

    test('全部为 System → system 聚合，messages 为空', () {
      final result = transformAnthropicMessages([
        message(ChatMessageRole.system, '系统一'),
        message(ChatMessageRole.system, '系统二'),
      ]);
      expect(result.system, '系统一\n系统二');
      expect(result.messages, isEmpty);
    });

    test('空列表 → system 为 null，messages 为空', () {
      final result = transformAnthropicMessages(const []);
      expect(result.system, isNull);
      expect(result.messages, isEmpty);
    });

    test('前导 System 内容为空字符串时仍计入 system', () {
      final result = transformAnthropicMessages([
        message(ChatMessageRole.system, ''),
        message(ChatMessageRole.user, '你好'),
      ]);
      expect(result.system, '');
      expect(result.messages, const [
        AnthropicTransformedMessage(role: 'user', content: '你好'),
      ]);
    });
  });

  group('中间 System → User', () {
    test('后续出现的 System 全部转为 User（并随后与相邻 User 合并）', () {
      final result = transformAnthropicMessages([
        message(ChatMessageRole.user, '你好'),
        message(ChatMessageRole.system, '中间指令'),
        message(ChatMessageRole.assistant, '回复'),
        message(ChatMessageRole.system, '又一条指令'),
      ]);
      expect(result.system, isNull);
      expect(result.messages, const [
        AnthropicTransformedMessage(role: 'user', content: '你好\n中间指令'),
        AnthropicTransformedMessage(role: 'assistant', content: '回复'),
        AnthropicTransformedMessage(role: 'user', content: '又一条指令'),
      ]);
    });
  });

  group('相邻同角色合并', () {
    test('user+user、assistant+assistant 单换行连接', () {
      final result = transformAnthropicMessages([
        message(ChatMessageRole.user, '第一段'),
        message(ChatMessageRole.user, '第二段'),
        message(ChatMessageRole.assistant, '回复一'),
        message(ChatMessageRole.assistant, '回复二'),
      ]);
      expect(result.system, isNull);
      expect(result.messages, const [
        AnthropicTransformedMessage(role: 'user', content: '第一段\n第二段'),
        AnthropicTransformedMessage(role: 'assistant', content: '回复一\n回复二'),
      ]);
    });

    test('System 转 User 后与相邻 User 合并', () {
      final result = transformAnthropicMessages([
        message(ChatMessageRole.user, '开头'),
        message(ChatMessageRole.system, '中间指令'),
        message(ChatMessageRole.user, '结尾'),
      ]);
      expect(result.system, isNull);
      expect(result.messages, const [
        AnthropicTransformedMessage(role: 'user', content: '开头\n中间指令\n结尾'),
      ]);
    });

    test('转 User 的 System 与前置 Assistant 不合并', () {
      final result = transformAnthropicMessages([
        message(ChatMessageRole.assistant, '回复'),
        message(ChatMessageRole.system, '指令'),
      ]);
      expect(result.messages, const [
        AnthropicTransformedMessage(role: 'assistant', content: '回复'),
        AnthropicTransformedMessage(role: 'user', content: '指令'),
      ]);
    });
  });

  group('角色集合与内容', () {
    test('输出 role 仅 user/assistant', () {
      final result = transformAnthropicMessages([
        message(ChatMessageRole.system, '系统'),
        message(ChatMessageRole.user, '你好'),
        message(ChatMessageRole.assistant, '回复'),
        message(ChatMessageRole.system, '中间'),
      ]);
      for (final transformed in result.messages) {
        expect(['user', 'assistant'], contains(transformed.role));
      }
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/request_message_filter.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

void main() {
  // ── 辅助工厂 ─────────────────────────────────────────────────

  ChatMessage message(String id, {String content = 'content'}) {
    return ChatMessage(
      id: id,
      role: ChatMessageRole.user,
      content: content,
      createdAt: DateTime(2026),
    );
  }

  List<String> ids(List<ChatMessage> messages) =>
      messages.map((m) => m.id).toList();

  // ── PassthroughMessageFilter ─────────────────────────────────

  group('PassthroughMessageFilter', () {
    test('原样返回不可变的消息快照', () {
      final messages = [message('a'), message('b'), message('c')];
      final result = RequestMessageFilter.passthrough.apply(messages);

      expect(ids(result), ['a', 'b', 'c']);
      expect(() => result.add(message('b')), throwsUnsupportedError);
    });
  });

  // ── ExcludeByIdMessageFilter ─────────────────────────────────

  group('ExcludeByIdMessageFilter', () {
    test('排除命中项，保留顺序且不修改输入，结果不可变', () {
      final messages = [message('a'), message('b'), message('c'), message('d')];
      final filter = const ExcludeByIdMessageFilter({'b', 'd'});
      final result = filter.apply(messages);

      expect(ids(result), ['a', 'c']);
      expect(ids(messages), ['a', 'b', 'c', 'd']);
      expect(() => result.add(message('e')), throwsUnsupportedError);
    });

    test('空排除集合等价于 passthrough', () {
      final messages = [message('a'), message('b')];
      const filter = ExcludeByIdMessageFilter({});

      expect(ids(filter.apply(messages)), ['a', 'b']);
    });
  });
}

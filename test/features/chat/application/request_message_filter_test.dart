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
    test('原样返回全部消息', () {
      final messages = [message('a'), message('b'), message('c')];
      final result = RequestMessageFilter.passthrough.apply(messages);

      expect(ids(result), ['a', 'b', 'c']);
    });

    test('空列表返回空列表', () {
      expect(RequestMessageFilter.passthrough.apply([]), isEmpty);
    });

    test('返回不可变列表，修改抛异常', () {
      final result = RequestMessageFilter.passthrough.apply([message('a')]);
      expect(() => result.add(message('b')), throwsUnsupportedError);
    });
  });

  // ── ExcludeByIdMessageFilter ─────────────────────────────────

  group('ExcludeByIdMessageFilter', () {
    test('排除命中项，保留其余且顺序不变', () {
      final messages = [message('a'), message('b'), message('c'), message('d')];
      final filter = const ExcludeByIdMessageFilter({'b', 'd'});

      expect(ids(filter.apply(messages)), ['a', 'c']);
    });

    test('空排除集合等价于 passthrough', () {
      final messages = [message('a'), message('b')];
      const filter = ExcludeByIdMessageFilter({});

      expect(ids(filter.apply(messages)), ['a', 'b']);
    });

    test('不含目标 id 时全部保留', () {
      final messages = [message('a'), message('b')];
      const filter = ExcludeByIdMessageFilter({'non-existent'});

      expect(ids(filter.apply(messages)), ['a', 'b']);
    });

    test('排除全部 id 返回空列表', () {
      final messages = [message('a'), message('b')];
      const filter = ExcludeByIdMessageFilter({'a', 'b'});

      expect(filter.apply(messages), isEmpty);
    });

    test('空输入返回空列表', () {
      const filter = ExcludeByIdMessageFilter({'a'});
      expect(filter.apply([]), isEmpty);
    });

    test('返回不可变列表，修改抛异常', () {
      final result = const ExcludeByIdMessageFilter({'b'}).apply(
        [message('a'), message('b')],
      );
      expect(() => result.add(message('c')), throwsUnsupportedError);
    });

    test('不修改原输入列表', () {
      final messages = [message('a'), message('b'), message('c')];
      const filter = ExcludeByIdMessageFilter({'b'});

      filter.apply(messages);
      expect(ids(messages), ['a', 'b', 'c']);
    });
  });

  // ── RequestMessageFilter.passthrough 静态常量 ─────────────────

  group('RequestMessageFilter.passthrough', () {
    test('是 PassthroughMessageFilter 实例', () {
      expect(RequestMessageFilter.passthrough, isA<PassthroughMessageFilter>());
    });

    test('const 实例同一性', () {
      const a = RequestMessageFilter.passthrough;
      const b = RequestMessageFilter.passthrough;
      expect(identical(a, b), isTrue);
    });
  });
}

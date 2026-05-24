import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/user_message_collapse.dart';

UserMessageSegment seg(String text, [UserMessageSegmentKind kind = UserMessageSegmentKind.body]) {
  return UserMessageSegment(text: text, kind: kind);
}

ChatMessage userMsg(String content) {
  return ChatMessage(
    id: 'test',
    role: ChatMessageRole.user,
    content: content,
    parentId: 'root',
    createdAt: DateTime(2026),
  );
}

ChatMessage assistantMsg(String content) {
  return ChatMessage(
    id: 'test',
    role: ChatMessageRole.assistant,
    content: content,
    parentId: 'root',
    createdAt: DateTime(2026),
  );
}

void main() {
  group('shouldCollapseUserMessage', () {
    test('非用户消息返回 false', () {
      expect(shouldCollapseUserMessage(assistantMsg('x' * 500)), isFalse);
    });

    test('用户消息行数 ≤ 20 返回 false', () {
      expect(shouldCollapseUserMessage(userMsg('line')), isFalse);
    });

    test('用户消息行数 = 20 返回 false（边界）', () {
      final content = List.filled(19, 'line').join('\n'); // 19个换行 = 20行
      expect(shouldCollapseUserMessage(userMsg(content)), isFalse);
    });

    test('用户消息行数 > 20 返回 true', () {
      final content = List.filled(21, 'line').join('\n'); // 20个换行 = 21行
      expect(shouldCollapseUserMessage(userMsg(content)), isTrue);
    });
  });

  group('countExplicitLines', () {
    test('空字符串计为 1 行', () {
      expect(countExplicitLines(''), 1);
    });

    test('单行（无换行符）计为 1 行', () {
      expect(countExplicitLines('hello'), 1);
    });

    test('末尾有换行符计为额外一行', () {
      expect(countExplicitLines('a\nb\n'), 3);
    });

    test('常规多行计数', () {
      expect(countExplicitLines('a\nb\nc'), 3);
    });
  });

  group('truncateContentToLines', () {
    test('行数 ≤ maxLines 时原样返回', () {
      expect(truncateContentToLines('a\nb\nc', 5), 'a\nb\nc');
    });

    test('行数 > maxLines 时截断', () {
      expect(truncateContentToLines('a\nb\nc\nd\ne', 3), 'a\nb\nc');
    });

    test('maxLines=1 只保留首行', () {
      expect(truncateContentToLines('a\nb', 1), 'a');
    });
  });

  group('truncateUserMessageSegments', () {
    test('空列表返回空列表', () {
      expect(truncateUserMessageSegments([], 100), isEmpty);
    });

    test('所有 segment 合计 ≤ maxLength 时原样返回', () {
      final result = truncateUserMessageSegments([seg('hello'), seg('world')], 10);
      expect(result.length, 2);
      expect(result[0].text, 'hello');
      expect(result[1].text, 'world');
    });

    test('部分 segment 超出时截断最后一条', () {
      final result = truncateUserMessageSegments([seg('hello'), seg('world')], 7);
      expect(result.length, 2);
      expect(result[0].text, 'hello');
      expect(result[1].text, 'wo');
      expect(result[1].kind, UserMessageSegmentKind.body);
    });

    test('第一个 segment 就超出时截断首条', () {
      final result = truncateUserMessageSegments([seg('hello')], 3);
      expect(result.length, 1);
      expect(result[0].text, 'hel');
    });

    test('maxLength=0 返回空列表', () {
      expect(truncateUserMessageSegments([seg('hello')], 0), isEmpty);
    });
  });
}

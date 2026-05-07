import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/domain/chat_conversation_groups.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';

void main() {
  ChatConversation conv(String id, DateTime updatedAt) {
    return ChatConversation(
      id: id,
      messages: const [],
      createdAt: updatedAt,
      updatedAt: updatedAt,
    );
  }

  ChatConversationSummary summary(String id, DateTime updatedAt) {
    return ChatConversationSummary(id: id, title: id, updatedAt: updatedAt);
  }

  group('groupConversationsByUpdatedAt', () {
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 4, 28, 12);
    });

    test('按核心时间桶分组', () {
      final groups = groupConversationsByUpdatedAt([
        conv('recent', now.subtract(const Duration(minutes: 10))),
        conv('day', now.subtract(const Duration(hours: 5))),
        conv('older', now.subtract(const Duration(days: 60))),
      ], now: now);

      expect(groups.map((group) => group.bucket), [
        ConversationTimeBucket.recent,
        ConversationTimeBucket.withinDay,
        ConversationTimeBucket.older,
      ]);
    });

    test('同一桶内按 updatedAt 降序排列', () {
      final groups = groupConversationsByUpdatedAt([
        conv('older', now.subtract(const Duration(hours: 3))),
        conv('newer', now.subtract(const Duration(hours: 2))),
      ], now: now);

      expect(groups.single.conversations.map((item) => item.id), [
        'newer',
        'older',
      ]);
    });

    test('空列表返回空分组列表', () {
      expect(groupConversationsByUpdatedAt([], now: now), isEmpty);
    });
  });

  group('groupConversationSummariesByUpdatedAt', () {
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 4, 28, 12);
    });

    test('summary 分组与排序行为保持一致', () {
      final groups = groupConversationSummariesByUpdatedAt([
        summary('newer', now.subtract(const Duration(hours: 2))),
        summary('older', now.subtract(const Duration(hours: 3))),
      ], now: now);

      expect(groups.single.conversations.map((item) => item.id), [
        'newer',
        'older',
      ]);
    });
  });
}

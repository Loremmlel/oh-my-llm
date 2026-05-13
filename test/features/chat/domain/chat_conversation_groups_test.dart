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

    test('按时间桶分组，并在桶内按 updatedAt 降序排列', () {
      expect(groupConversationsByUpdatedAt([], now: now), isEmpty);

      final groups = groupConversationsByUpdatedAt([
        conv('recent-older', now.subtract(const Duration(minutes: 20))),
        conv('within-day', now.subtract(const Duration(hours: 5))),
        conv('recent-newer', now.subtract(const Duration(minutes: 10))),
        conv('older', now.subtract(const Duration(days: 60))),
      ], now: now);

      expect(groups.map((group) => group.bucket), [
        ConversationTimeBucket.recent,
        ConversationTimeBucket.withinDay,
        ConversationTimeBucket.older,
      ]);
      expect(groups.first.conversations.map((item) => item.id), [
        'recent-newer',
        'recent-older',
      ]);
      expect(groups[1].conversations.single.id, 'within-day');
      expect(groups[2].conversations.single.id, 'older');
    });
  });

  group('groupConversationSummariesByUpdatedAt', () {
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 4, 28, 12);
    });

    test('summary 分组与排序行为与 conversations 保持一致', () {
      final groups = groupConversationSummariesByUpdatedAt([
        summary('recent-older', now.subtract(const Duration(minutes: 20))),
        summary('within-day', now.subtract(const Duration(hours: 5))),
        summary('recent-newer', now.subtract(const Duration(minutes: 10))),
      ], now: now);

      expect(groups.map((group) => group.bucket), [
        ConversationTimeBucket.recent,
        ConversationTimeBucket.withinDay,
      ]);
      expect(groups.first.conversations.map((item) => item.id), [
        'recent-newer',
        'recent-older',
      ]);
      expect(groups[1].conversations.single.id, 'within-day');
    });
  });
}

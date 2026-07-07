import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/domain/chat_conversation_groups.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';

void main() {
  // ── 辅助工厂 ─────────────────────────────────────────────────

  final now = DateTime(2026, 6, 1, 12);

  ChatConversationSummary conv(
    String id, {
    required Duration age,
    String? title,
  }) {
    return ChatConversationSummary(
      id: id,
      title: title,
      updatedAt: now.subtract(age),
    );
  }

  // ── groupConversationSummariesByUpdatedAt ────────────────────

  group('groupConversationSummariesByUpdatedAt', () {
    test('空输入返回空列表', () {
      expect(groupConversationSummariesByUpdatedAt([], now: now), isEmpty);
    });

    test('各年龄会话落入对应时间桶', () {
      final conversations = [
        conv('recent', age: const Duration(minutes: 30)),
        conv('withinDay', age: const Duration(hours: 5)),
        conv('withinThreeDays', age: const Duration(days: 2)),
        conv('withinWeek', age: const Duration(days: 6)),
        conv('withinMonth', age: const Duration(days: 20)),
        conv('older', age: const Duration(days: 60)),
      ];

      final groups = groupConversationSummariesByUpdatedAt(
        conversations,
        now: now,
      );

      expect(groups.map((g) => g.bucket).toList(), [
        ConversationTimeBucket.recent,
        ConversationTimeBucket.withinDay,
        ConversationTimeBucket.withinThreeDays,
        ConversationTimeBucket.withinWeek,
        ConversationTimeBucket.withinMonth,
        ConversationTimeBucket.older,
      ]);
      expect(groups[0].conversations.single.id, 'recent');
      expect(groups[5].conversations.single.id, 'older');
    });

    test('边界值：刚好 1h 落入 withinDay 而非 recent', () {
      final conversations = [
        conv('boundary-1h', age: const Duration(hours: 1)),
      ];

      final groups = groupConversationSummariesByUpdatedAt(
        conversations,
        now: now,
      );

      expect(groups.single.bucket, ConversationTimeBucket.withinDay);
    });

    test('边界值：刚好 1d 落入 withinThreeDays', () {
      final groups = groupConversationSummariesByUpdatedAt(
        [conv('boundary-1d', age: const Duration(days: 1))],
        now: now,
      );
      expect(groups.single.bucket, ConversationTimeBucket.withinThreeDays);
    });

    test('边界值：刚好 3d 落入 withinWeek', () {
      final groups = groupConversationSummariesByUpdatedAt(
        [conv('boundary-3d', age: const Duration(days: 3))],
        now: now,
      );
      expect(groups.single.bucket, ConversationTimeBucket.withinWeek);
    });

    test('边界值：刚好 7d 落入 withinMonth', () {
      final groups = groupConversationSummariesByUpdatedAt(
        [conv('boundary-7d', age: const Duration(days: 7))],
        now: now,
      );
      expect(groups.single.bucket, ConversationTimeBucket.withinMonth);
    });

    test('边界值：刚好 30d 落入 older', () {
      final groups = groupConversationSummariesByUpdatedAt(
        [conv('boundary-30d', age: const Duration(days: 30))],
        now: now,
      );
      expect(groups.single.bucket, ConversationTimeBucket.older);
    });

    test('同桶内按 updatedAt 降序排列', () {
      final conversations = [
        conv('old', age: const Duration(hours: 3)),
        conv('new', age: const Duration(hours: 1)),
        conv('mid', age: const Duration(hours: 2)),
      ];

      final groups = groupConversationSummariesByUpdatedAt(
        conversations,
        now: now,
      );

      expect(groups.single.bucket, ConversationTimeBucket.withinDay);
      expect(
        groups.single.conversations.map((c) => c.id).toList(),
        ['new', 'mid', 'old'],
      );
    });

    test('空桶不出现在结果中', () {
      final conversations = [
        conv('only-recent', age: const Duration(minutes: 10)),
      ];

      final groups = groupConversationSummariesByUpdatedAt(
        conversations,
        now: now,
      );

      expect(groups, hasLength(1));
      expect(groups.single.bucket, ConversationTimeBucket.recent);
    });

    test('桶顺序遵循枚举声明顺序', () {
      final conversations = [
        conv('older', age: const Duration(days: 60)),
        conv('recent', age: const Duration(minutes: 10)),
      ];

      final groups = groupConversationSummariesByUpdatedAt(
        conversations,
        now: now,
      );

      expect(groups.first.bucket, ConversationTimeBucket.recent);
      expect(groups.last.bucket, ConversationTimeBucket.older);
    });

    test('未提供 now 时回退到 DateTime.now() 且不抛异常', () {
      expect(
        () => groupConversationSummariesByUpdatedAt(
          [conv('c1', age: const Duration(minutes: 5))],
        ),
        returnsNormally,
      );
    });
  });

  // ── flattenConversationSummaryGroups ─────────────────────────

  group('flattenConversationSummaryGroups', () {
    test('空分组列表返回空列表', () {
      expect(flattenConversationSummaryGroups([]), isEmpty);
    });

    test('输出 bucket 与 summary 交错排列', () {
      final conversations = [
        conv('a', age: const Duration(minutes: 10)),
        conv('b', age: const Duration(minutes: 20)),
      ];

      final groups = groupConversationSummariesByUpdatedAt(
        conversations,
        now: now,
      );

      final flat = flattenConversationSummaryGroups(groups);

      // [bucket, summary, summary]
      expect(flat, hasLength(3));
      expect(flat[0], isA<ConversationTimeBucket>());
      expect(flat[1], isA<ChatConversationSummary>());
      expect(flat[2], isA<ChatConversationSummary>());
    });

    test('多个桶时交错结构正确', () {
      final conversations = [
        conv('recent', age: const Duration(minutes: 10)),
        conv('older', age: const Duration(days: 60)),
      ];

      final groups = groupConversationSummariesByUpdatedAt(
        conversations,
        now: now,
      );

      final flat = flattenConversationSummaryGroups(groups);

      // [recent-bucket, recent-summary, older-bucket, older-summary]
      expect(flat, hasLength(4));
      expect(flat[0], isA<ConversationTimeBucket>());
      expect(flat[1], isA<ChatConversationSummary>());
      expect(flat[2], isA<ConversationTimeBucket>());
      expect(flat[3], isA<ChatConversationSummary>());
    });
  });

  // ── ConversationTimeBucket ───────────────────────────────────

  group('ConversationTimeBucket', () {
    test('各桶 label 非空', () {
      for (final bucket in ConversationTimeBucket.values) {
        expect(bucket.label, isNotEmpty);
      }
    });

    test('枚举顺序从新到旧', () {
      expect(ConversationTimeBucket.values.first, ConversationTimeBucket.recent);
      expect(ConversationTimeBucket.values.last, ConversationTimeBucket.older);
    });
  });
}

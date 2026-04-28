import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/domain/chat_conversation_groups.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation_summary.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

void main() {
  // ── 辅助函数 ─────────────────────────────────────────────────────────────

  /// 构造仅包含 updatedAt 的最简 ChatConversation。
  ChatConversation _conv(String id, DateTime updatedAt) {
    return ChatConversation(
      id: id,
      messages: const [],
      createdAt: updatedAt,
      updatedAt: updatedAt,
    );
  }

  /// 构造 ChatConversationSummary。
  ChatConversationSummary _summary(String id, DateTime updatedAt) {
    return ChatConversationSummary(
      id: id,
      title: id,
      updatedAt: updatedAt,
    );
  }

  // ── 时间桶边界值 ──────────────────────────────────────────────────────────

  group('groupConversationsByUpdatedAt 时间桶分配', () {
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 4, 28, 12);
    });

    test('0 分钟前 → recent', () {
      final groups = groupConversationsByUpdatedAt(
        [_conv('c1', now)],
        now: now,
      );
      expect(groups.single.bucket, ConversationTimeBucket.recent);
    });

    test('59 分钟前 → recent', () {
      final groups = groupConversationsByUpdatedAt(
        [_conv('c1', now.subtract(const Duration(minutes: 59)))],
        now: now,
      );
      expect(groups.single.bucket, ConversationTimeBucket.recent);
    });

    test('恰好 1 小时前 → withinDay', () {
      final groups = groupConversationsByUpdatedAt(
        [_conv('c1', now.subtract(const Duration(hours: 1)))],
        now: now,
      );
      expect(groups.single.bucket, ConversationTimeBucket.withinDay);
    });

    test('23 小时前 → withinDay', () {
      final groups = groupConversationsByUpdatedAt(
        [_conv('c1', now.subtract(const Duration(hours: 23)))],
        now: now,
      );
      expect(groups.single.bucket, ConversationTimeBucket.withinDay);
    });

    test('恰好 1 天前 → withinThreeDays', () {
      final groups = groupConversationsByUpdatedAt(
        [_conv('c1', now.subtract(const Duration(days: 1)))],
        now: now,
      );
      expect(groups.single.bucket, ConversationTimeBucket.withinThreeDays);
    });

    test('2 天 23 小时前 → withinThreeDays', () {
      final groups = groupConversationsByUpdatedAt(
        [
          _conv(
            'c1',
            now.subtract(const Duration(days: 2, hours: 23)),
          ),
        ],
        now: now,
      );
      expect(groups.single.bucket, ConversationTimeBucket.withinThreeDays);
    });

    test('恰好 3 天前 → withinWeek', () {
      final groups = groupConversationsByUpdatedAt(
        [_conv('c1', now.subtract(const Duration(days: 3)))],
        now: now,
      );
      expect(groups.single.bucket, ConversationTimeBucket.withinWeek);
    });

    test('6 天前 → withinWeek', () {
      final groups = groupConversationsByUpdatedAt(
        [_conv('c1', now.subtract(const Duration(days: 6)))],
        now: now,
      );
      expect(groups.single.bucket, ConversationTimeBucket.withinWeek);
    });

    test('恰好 7 天前 → withinMonth', () {
      final groups = groupConversationsByUpdatedAt(
        [_conv('c1', now.subtract(const Duration(days: 7)))],
        now: now,
      );
      expect(groups.single.bucket, ConversationTimeBucket.withinMonth);
    });

    test('29 天前 → withinMonth', () {
      final groups = groupConversationsByUpdatedAt(
        [_conv('c1', now.subtract(const Duration(days: 29)))],
        now: now,
      );
      expect(groups.single.bucket, ConversationTimeBucket.withinMonth);
    });

    test('恰好 30 天前 → older', () {
      final groups = groupConversationsByUpdatedAt(
        [_conv('c1', now.subtract(const Duration(days: 30)))],
        now: now,
      );
      expect(groups.single.bucket, ConversationTimeBucket.older);
    });

    test('100 天前 → older', () {
      final groups = groupConversationsByUpdatedAt(
        [_conv('c1', now.subtract(const Duration(days: 100)))],
        now: now,
      );
      expect(groups.single.bucket, ConversationTimeBucket.older);
    });
  });

  // ── 分组与排序 ────────────────────────────────────────────────────────────

  group('groupConversationsByUpdatedAt 分组排序', () {
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 4, 28, 12);
    });

    test('不同时间桶的会话分到不同组', () {
      final convs = [
        _conv('recent', now.subtract(const Duration(minutes: 10))),
        _conv('day', now.subtract(const Duration(hours: 5))),
        _conv('older', now.subtract(const Duration(days: 60))),
      ];

      final groups = groupConversationsByUpdatedAt(convs, now: now);

      expect(groups, hasLength(3));
      expect(groups.map((g) => g.bucket), containsAll([
        ConversationTimeBucket.recent,
        ConversationTimeBucket.withinDay,
        ConversationTimeBucket.older,
      ]));
    });

    test('同一桶内按 updatedAt 降序排列', () {
      final older = now.subtract(const Duration(hours: 3));
      final newer = now.subtract(const Duration(hours: 2));
      final convs = [
        _conv('c-older', older),
        _conv('c-newer', newer),
      ];

      final groups = groupConversationsByUpdatedAt(convs, now: now);

      expect(groups, hasLength(1));
      final items = groups.single.conversations;
      expect(items[0].id, 'c-newer');
      expect(items[1].id, 'c-older');
    });

    test('输出列表按桶枚举顺序排列', () {
      final convs = [
        _conv('c-older', now.subtract(const Duration(days: 60))),
        _conv('c-day', now.subtract(const Duration(hours: 5))),
        _conv('c-recent', now.subtract(const Duration(minutes: 10))),
      ];

      final groups = groupConversationsByUpdatedAt(convs, now: now);

      expect(groups[0].bucket, ConversationTimeBucket.recent);
      expect(groups[1].bucket, ConversationTimeBucket.withinDay);
      expect(groups[2].bucket, ConversationTimeBucket.older);
    });

    test('空列表返回空分组列表', () {
      final groups = groupConversationsByUpdatedAt([], now: now);
      expect(groups, isEmpty);
    });

    test('单条会话返回单组单条', () {
      final groups = groupConversationsByUpdatedAt(
        [_conv('only', now.subtract(const Duration(minutes: 5)))],
        now: now,
      );
      expect(groups, hasLength(1));
      expect(groups.single.conversations.single.id, 'only');
    });

    test('未传 now 时使用当前系统时间（不抛出异常）', () {
      // 不传 now，只验证调用不崩溃、能返回分组。
      final groups = groupConversationsByUpdatedAt([
        _conv('c', DateTime.now().subtract(const Duration(minutes: 1))),
      ]);
      expect(groups, hasLength(1));
    });
  });

  // ── groupConversationSummariesByUpdatedAt ────────────────────────────────

  group('groupConversationSummariesByUpdatedAt', () {
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 4, 28, 12);
    });

    test('按桶分组与 groupConversationsByUpdatedAt 行为一致', () {
      final summaries = [
        _summary('s-recent', now.subtract(const Duration(minutes: 10))),
        _summary('s-older', now.subtract(const Duration(days: 60))),
      ];

      final groups = groupConversationSummariesByUpdatedAt(
        summaries,
        now: now,
      );

      expect(groups, hasLength(2));
      expect(groups[0].bucket, ConversationTimeBucket.recent);
      expect(groups[1].bucket, ConversationTimeBucket.older);
    });

    test('同一桶内按 updatedAt 降序排列', () {
      final summaries = [
        _summary('s-old', now.subtract(const Duration(hours: 3))),
        _summary('s-new', now.subtract(const Duration(hours: 2))),
      ];

      final groups = groupConversationSummariesByUpdatedAt(
        summaries,
        now: now,
      );

      expect(groups.single.conversations[0].id, 's-new');
      expect(groups.single.conversations[1].id, 's-old');
    });

    test('空列表返回空', () {
      final groups = groupConversationSummariesByUpdatedAt([], now: now);
      expect(groups, isEmpty);
    });
  });
}

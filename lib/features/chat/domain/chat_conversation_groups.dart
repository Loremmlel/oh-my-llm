import 'models/chat_conversation.dart';
import 'models/chat_conversation_summary.dart';

/// 历史会话分组所使用的时间桶。
enum ConversationTimeBucket {
  recent('最近'),
  withinDay('一天内'),
  withinThreeDays('三天内'),
  withinWeek('一周内'),
  withinMonth('一月内'),
  older('更早');

  const ConversationTimeBucket(this.label);

  final String label;
}

/// 按更新时间分组后的会话集合。
class ChatConversationGroup {
  const ChatConversationGroup({
    required this.bucket,
    required this.conversations,
  });

  final ConversationTimeBucket bucket;
  final List<ChatConversation> conversations;
}

/// 按更新时间分组后的轻量会话摘要集合。
class ChatConversationSummaryGroup {
  const ChatConversationSummaryGroup({
    required this.bucket,
    required this.conversations,
  });

  final ConversationTimeBucket bucket;
  final List<ChatConversationSummary> conversations;
}

/// 按更新时间把会话拆分到不同时间桶中。
List<ChatConversationGroup> groupConversationsByUpdatedAt(
  List<ChatConversation> conversations, {
  DateTime? now,
}) {
  final grouped = _groupItemsByUpdatedAt(
    conversations,
    now: now,
    updatedAtOf: (conversation) => conversation.updatedAt,
  );

  return grouped
      .map((group) {
        return ChatConversationGroup(
          bucket: group.bucket,
          conversations: group.items,
        );
      })
      .toList(growable: false);
}

/// 按更新时间把会话摘要拆分到不同时间桶中。
List<ChatConversationSummaryGroup> groupConversationSummariesByUpdatedAt(
  List<ChatConversationSummary> conversations, {
  DateTime? now,
}) {
  final grouped = _groupItemsByUpdatedAt(
    conversations,
    now: now,
    updatedAtOf: (conversation) => conversation.updatedAt,
  );

  return grouped
      .map((group) {
        return ChatConversationSummaryGroup(
          bucket: group.bucket,
          conversations: group.items,
        );
      })
      .toList(growable: false);
}

class _ConversationGroupItems<T> {
  const _ConversationGroupItems({required this.bucket, required this.items});

  final ConversationTimeBucket bucket;
  final List<T> items;
}

List<_ConversationGroupItems<T>> _groupItemsByUpdatedAt<T>(
  List<T> items, {
  DateTime? now,
  required DateTime Function(T item) updatedAtOf,
}) {
  final referenceTime = now ?? DateTime.now();
  final grouped = <ConversationTimeBucket, List<T>>{};

  for (final item in items) {
    final bucket = _resolveBucket(referenceTime.difference(updatedAtOf(item)));
    grouped.putIfAbsent(bucket, () => <T>[]).add(item);
  }

  return ConversationTimeBucket.values
      .where(grouped.containsKey)
      .map<_ConversationGroupItems<T>>((bucket) {
        final bucketItems = grouped[bucket]!
          ..sort((left, right) {
            return updatedAtOf(right).compareTo(updatedAtOf(left));
          });
        return _ConversationGroupItems<T>(
          bucket: bucket,
          items: List.unmodifiable(bucketItems),
        );
      })
      .toList(growable: false);
}

/// 根据会话年龄选择对应的时间桶。
ConversationTimeBucket _resolveBucket(Duration age) {
  if (age < const Duration(hours: 1)) {
    return ConversationTimeBucket.recent;
  }
  if (age < const Duration(days: 1)) {
    return ConversationTimeBucket.withinDay;
  }
  if (age < const Duration(days: 3)) {
    return ConversationTimeBucket.withinThreeDays;
  }
  if (age < const Duration(days: 7)) {
    return ConversationTimeBucket.withinWeek;
  }
  if (age < const Duration(days: 30)) {
    return ConversationTimeBucket.withinMonth;
  }

  return ConversationTimeBucket.older;
}

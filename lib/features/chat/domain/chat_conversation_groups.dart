import 'models/chat_conversation.dart';

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

class ChatConversationGroup {
  const ChatConversationGroup({
    required this.bucket,
    required this.conversations,
  });

  final ConversationTimeBucket bucket;
  final List<ChatConversation> conversations;
}

List<ChatConversationGroup> groupConversationsByUpdatedAt(
  List<ChatConversation> conversations, {
  DateTime? now,
}) {
  final referenceTime = now ?? DateTime.now();
  final grouped = <ConversationTimeBucket, List<ChatConversation>>{};

  for (final conversation in conversations) {
    final bucket = _resolveBucket(
      referenceTime.difference(conversation.updatedAt),
    );
    grouped.putIfAbsent(bucket, () => <ChatConversation>[]).add(conversation);
  }

  return ConversationTimeBucket.values
      .where(grouped.containsKey)
      .map((bucket) {
        final bucketConversations = grouped[bucket]!..sort((left, right) {
          return right.updatedAt.compareTo(left.updatedAt);
        });
        return ChatConversationGroup(
          bucket: bucket,
          conversations: List.unmodifiable(bucketConversations),
        );
      })
      .toList(growable: false);
}

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

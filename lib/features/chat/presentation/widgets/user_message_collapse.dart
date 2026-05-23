import '../../domain/models/chat_message.dart';

const int maxUserMessageLines = 20;

bool shouldCollapseUserMessage(ChatMessage message) {
  if (message.role != ChatMessageRole.user) {
    return false;
  }
  return countExplicitLines(message.content) > maxUserMessageLines;
}

int countExplicitLines(String content) {
  if (content.isEmpty) {
    return 1;
  }
  return '\n'.allMatches(content).length + 1;
}

String truncateContentToLines(String content, int maxLines) {
  final lines = content.split('\n');
  if (lines.length <= maxLines) {
    return content;
  }
  return lines.take(maxLines).join('\n');
}

List<UserMessageSegment> truncateUserMessageSegments(
  List<UserMessageSegment> segments,
  int maxLength,
) {
  var remaining = maxLength;
  final result = <UserMessageSegment>[];
  for (final segment in segments) {
    if (remaining <= 0) {
      break;
    }
    if (segment.text.length <= remaining) {
      result.add(segment);
      remaining -= segment.text.length;
      continue;
    }
    result.add(
      UserMessageSegment(
        text: segment.text.substring(0, remaining),
        kind: segment.kind,
      ),
    );
    break;
  }
  return result;
}

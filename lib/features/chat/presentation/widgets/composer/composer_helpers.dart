import '../../../domain/models/chat_message.dart';

String effortLabel(ReasoningEffort effort) {
  return switch (effort) {
    ReasoningEffort.low => 'low',
    ReasoningEffort.medium => 'med',
    ReasoningEffort.high => 'high',
    ReasoningEffort.xhigh => 'xhigh',
  };
}

String messageFilterLabel(int excludedMessageCount) {
  if (excludedMessageCount <= 0) {
    return '上下文过滤';
  }
  return '上下文过滤 · 已排除 $excludedMessageCount 条';
}

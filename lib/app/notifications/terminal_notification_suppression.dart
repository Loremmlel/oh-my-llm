import 'package:oh_my_llm/app/attention/app_attention_state.dart';
import 'package:oh_my_llm/app/navigation/app_destination.dart';

/// 终态通知注意力抑制的共享判定。
///
/// 供默认终态通知深模块（执行时刻回退）与 app composition（终态事件发生
/// 时刻冻结）共用同一逻辑，避免两处实现分叉。
///
/// [readActiveConversationId] 惰性求值：仅宿主 attentive 且路由精确等于
/// /chat 时才读取，非 /chat 页面不无谓读取会话 ID（深模块既有契约）。
bool isTerminalNotificationSuppressed({
  required AppAttentionState attention,
  required String Function() readActiveConversationId,
  required String conversationId,
}) {
  if (!attention.hostIsAttentive) return false;
  if (attention.location.path != AppDestination.chat.path) return false;
  return readActiveConversationId() == conversationId;
}

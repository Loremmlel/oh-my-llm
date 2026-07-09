import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 聊天页"模板提示词"选择的内存级记忆。
///
/// 模板提示词仅用于拼接下一次发送的用户消息，属于一次性输入偏好而非会话级
/// 持久化配置，因此不写回 [ChatConversation] 与 SQLite。
///
/// 使用全局 [NotifierProvider] 让选择状态脱离 [ChatScreen] 的本地 State，
/// 在 GoRouter 页面切换（销毁重建 ChatScreen）后仍能恢复，避免每次回到
/// 聊天页都要重新选择模板。切换会话或新建会话时由调用方主动清空，
/// 避免上一会话的模板选择残留到新会话。
///
/// 注意：当前为全局单例，多窗口/多实例场景下共享同一选择状态。
/// 若未来支持多窗口并行聊天，需改为 family provider 或 scoped override。
class ChatTemplatePromptSelectionController extends Notifier<String?> {
  @override
  String? build() => null;

  /// 更新当前选中的模板提示词 ID，null 表示不使用模板。
  void select(String? templatePromptId) {
    if (state == templatePromptId) return;
    state = templatePromptId;
  }

  /// 清空当前选择。
  void clear() {
    if (state == null) return;
    state = null;
  }
}

/// 当前选中的模板提示词 ID（内存级，跨页面保留，App 重启后重置）。
final chatTemplatePromptSelectionProvider =
    NotifierProvider<ChatTemplatePromptSelectionController, String?>(
  ChatTemplatePromptSelectionController.new,
);

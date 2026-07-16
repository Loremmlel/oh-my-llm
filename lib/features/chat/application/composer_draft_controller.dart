import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 聊天输入框草稿的内存级持久化。
///
/// 正文草稿按会话 ID 隔离；模板变量草稿按 `templateId::variableName` 隔离。
/// 仅存于内存，跨 GoRouter 页面切换（销毁重建 [ChatScreen]）后仍能恢复，
/// App 重启后重置——无需写回 SharedPreferences / SQLite。
class ComposerDraftState {
  const ComposerDraftState({
    this.bodyByConversationId = const {},
    this.templateVariableValues = const {},
  });

  /// 正文草稿，key = 会话 ID。
  final Map<String, String> bodyByConversationId;

  /// 模板变量草稿，key = `templateId::variableName`。
  final Map<String, String> templateVariableValues;

  ComposerDraftState copyWith({
    Map<String, String>? bodyByConversationId,
    Map<String, String>? templateVariableValues,
  }) {
    return ComposerDraftState(
      bodyByConversationId: bodyByConversationId ?? this.bodyByConversationId,
      templateVariableValues:
          templateVariableValues ?? this.templateVariableValues,
    );
  }
}

class ComposerDraftController extends Notifier<ComposerDraftState> {
  @override
  ComposerDraftState build() => const ComposerDraftState();

  static String _variableKey(String templateId, String variableName) =>
      '$templateId::$variableName';

  /// 读取指定会话的正文草稿，无草稿返回 null。
  String? readBody(String conversationId) =>
      state.bodyByConversationId[conversationId];

  /// 写入/更新指定会话的正文草稿。
  void setBody(String conversationId, String body) {
    if (state.bodyByConversationId[conversationId] == body) return;
    final next = Map<String, String>.from(state.bodyByConversationId)
      ..[conversationId] = body;
    state = state.copyWith(bodyByConversationId: next);
  }

  /// 清空指定会话的正文草稿。
  void clearBody(String conversationId) {
    if (!state.bodyByConversationId.containsKey(conversationId)) return;
    final next = Map<String, String>.from(state.bodyByConversationId)
      ..remove(conversationId);
    state = state.copyWith(bodyByConversationId: next);
  }

  /// 读取模板变量草稿，无草稿返回 null。
  String? readTemplateVariable(String templateId, String variableName) =>
      state.templateVariableValues[_variableKey(templateId, variableName)];

  /// 写入/更新模板变量草稿。
  void setTemplateVariable(
    String templateId,
    String variableName,
    String value,
  ) {
    final key = _variableKey(templateId, variableName);
    if (state.templateVariableValues[key] == value) return;
    final next = Map<String, String>.from(state.templateVariableValues)
      ..[key] = value;
    state = state.copyWith(templateVariableValues: next);
  }
}

/// 聊天输入框草稿（内存级，跨页面保留，App 重启后重置）。
final composerDraftProvider =
    NotifierProvider<ComposerDraftController, ComposerDraftState>(
  ComposerDraftController.new,
);

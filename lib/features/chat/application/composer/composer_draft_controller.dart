import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 单个会话的输入草稿：正文、模板选择、模板变量。
///
/// 值对象不可变：构造/copy 时对每层嵌套 Map 做防御复制并 `Map.unmodifiable`，
/// 避免外层包成 unmodifiable 后仍暴露可变内层。仅存于内存并按会话隔离，
/// 跨 GoRouter 页面切换（销毁重建 [ChatScreen]）后仍能恢复，App 重启后重置。
class ComposerDraft extends Equatable {
  const ComposerDraft({
    this.body = '',
    this.selectedTemplatePromptId,
    this.templateVariableValuesByTemplateId = const {},
  });

  /// 无任何内容/选择的空草稿，供 absent 会话回退。
  static const empty = ComposerDraft();

  final String body;
  final String? selectedTemplatePromptId;

  /// key = 模板 ID，value = 该模板的 {变量名: 值}。
  final Map<String, Map<String, String>> templateVariableValuesByTemplateId;

  ComposerDraft copyWith({
    String? body,
    String? selectedTemplatePromptId,
    bool clearTemplateSelection = false,
    Map<String, Map<String, String>>? templateVariableValuesByTemplateId,
  }) {
    return ComposerDraft(
      body: body ?? this.body,
      selectedTemplatePromptId: clearTemplateSelection
          ? null
          : selectedTemplatePromptId ?? this.selectedTemplatePromptId,
      templateVariableValuesByTemplateId: _deepCopy(
        templateVariableValuesByTemplateId ??
            this.templateVariableValuesByTemplateId,
      ),
    );
  }

  static Map<String, Map<String, String>> _deepCopy(
    Map<String, Map<String, String>> source,
  ) {
    // `Map.unmodifiable` 的形参是 `Map<dynamic, dynamic>`，裸调用会对嵌套 map
    // 推断成 `Map<dynamic,dynamic>`，运行时整体 cast 成 `Map<String,String>` 失败。
    // 显式标注内层类型，让每层都保持具体泛型。
    return Map<String, Map<String, String>>.unmodifiable(
      source.map(
        (templateId, variables) =>
            MapEntry(templateId, Map<String, String>.unmodifiable(variables)),
      ),
    );
  }

  @override
  List<Object?> get props => [
    body,
    selectedTemplatePromptId,
    templateVariableValuesByTemplateId,
  ];
}

/// 全部会话的体草稿集合。
class ComposerDraftState extends Equatable {
  const ComposerDraftState({this.draftsByConversationId = const {}});

  final Map<String, ComposerDraft> draftsByConversationId;

  ComposerDraftState copyWith({
    Map<String, ComposerDraft>? draftsByConversationId,
  }) {
    return ComposerDraftState(
      draftsByConversationId: Map.unmodifiable(
        draftsByConversationId ?? this.draftsByConversationId,
      ),
    );
  }

  @override
  List<Object?> get props => [draftsByConversationId];
}

class ComposerDraftController extends Notifier<ComposerDraftState> {
  @override
  ComposerDraftState build() => const ComposerDraftState();

  /// 读取指定会话草稿，无草稿返回 [ComposerDraft.empty]。
  ComposerDraft draftFor(String conversationId) =>
      state.draftsByConversationId[conversationId] ?? ComposerDraft.empty;

  /// 写入/更新正文；相同值不发 state。
  void setBody(String conversationId, String body) {
    final current = draftFor(conversationId);
    if (current.body == body) return;
    state = state.copyWith(
      draftsByConversationId: {
        ...state.draftsByConversationId,
        conversationId: current.copyWith(body: body),
      },
    );
  }

  /// 更新模板选择；相同值不发 state。
  void selectTemplate(String conversationId, String? templatePromptId) {
    final current = draftFor(conversationId);
    if (current.selectedTemplatePromptId == templatePromptId) return;
    state = state.copyWith(
      draftsByConversationId: {
        ...state.draftsByConversationId,
        conversationId: current.copyWith(
          selectedTemplatePromptId: templatePromptId,
          clearTemplateSelection: templatePromptId == null,
        ),
      },
    );
  }

  /// 写入/更新模板变量；相同值不发 state。
  void setTemplateVariable(
    String conversationId,
    String templateId,
    String variableName,
    String value,
  ) {
    final current = draftFor(conversationId);
    final templateVariables = Map<String, String>.from(
      current.templateVariableValuesByTemplateId[templateId] ?? const {},
    );
    if (templateVariables[variableName] == value) return;
    templateVariables[variableName] = value;
    final nextVariables = Map<String, Map<String, String>>.from(
      current.templateVariableValuesByTemplateId,
    )..[templateId] = Map<String, String>.unmodifiable(templateVariables);
    state = state.copyWith(
      draftsByConversationId: {
        ...state.draftsByConversationId,
        conversationId: current.copyWith(
          templateVariableValuesByTemplateId: nextVariables,
        ),
      },
    );
  }

  /// 整体替换草稿（仅恢复/提交事务使用）。
  ///
  /// state 入口处的防御复制：外部构造的 draft 内层 map 可能可变，
  /// 直接存储会破坏不可变性契约，故先深拷贝再放入 state。
  void replaceDraft(String conversationId, ComposerDraft draft) {
    state = state.copyWith(
      draftsByConversationId: {
        ...state.draftsByConversationId,
        conversationId: draft.copyWith(),
      },
    );
  }

  /// 整体替换所选模板的嵌套变量 map。
  ///
  /// 仅当长度或任一 key/value 有差异时才写入 state；Dart 的 `Map.==` 是同一性
  /// 比较，不能用来判断内容相等，故逐项比较。只替换目标模板的嵌套 map，
  /// 保留正文、模板选择、其他模板草稿与其他会话草稿。
  void replaceTemplateVariables(
    String conversationId,
    String templateId,
    Map<String, String> values,
  ) {
    final current = draftFor(conversationId);
    final currentTemplateVariables =
        current.templateVariableValuesByTemplateId[templateId] ?? const {};
    final nextTemplateVariables = Map<String, String>.unmodifiable(values);
    if (_sameStringMap(currentTemplateVariables, nextTemplateVariables)) {
      return;
    }
    final nextVariables = Map<String, Map<String, String>>.from(
      current.templateVariableValuesByTemplateId,
    )..[templateId] = nextTemplateVariables;
    state = state.copyWith(
      draftsByConversationId: {
        ...state.draftsByConversationId,
        conversationId: current.copyWith(
          templateVariableValuesByTemplateId: nextVariables,
        ),
      },
    );
  }

  /// 逐项比较两张字符串 map 的内容是否相等（Dart `Map.==` 是同一性比较）。
  static bool _sameStringMap(
    Map<String, String> first,
    Map<String, String> second,
  ) {
    if (first.length != second.length) {
      return false;
    }
    for (final entry in first.entries) {
      if (second[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  /// send 后清空正文，但保留模板选择与变量草稿。
  void clearBody(String conversationId) {
    final current = draftFor(conversationId);
    if (current.body.isEmpty) return;
    state = state.copyWith(
      draftsByConversationId: {
        ...state.draftsByConversationId,
        conversationId: current.copyWith(body: ''),
      },
    );
  }

  /// 「新对话」显式重置整个草稿。
  void clearDraft(String conversationId) {
    if (!state.draftsByConversationId.containsKey(conversationId)) return;
    final next = Map<String, ComposerDraft>.from(state.draftsByConversationId)
      ..remove(conversationId);
    state = state.copyWith(draftsByConversationId: next);
  }
}

/// 聊天输入框草稿（内存级，跨页面保留，App 重启后重置）。
final composerDraftProvider =
    NotifierProvider<ComposerDraftController, ComposerDraftState>(
      ComposerDraftController.new,
    );

/// 只监听指定会话的模板选择，供 [ChatScreen] 用 `.select` 派生。
///
/// 每次正文/变量写入不会让整个 [ChatScreen] rebuild；只有选择变化才触发。
final composerTemplateSelectionProvider = Provider.family<String?, String>((
  ref,
  conversationId,
) {
  return ref.watch(
    composerDraftProvider.select(
      (state) => state
          .draftsByConversationId[conversationId]
          ?.selectedTemplatePromptId,
    ),
  );
});

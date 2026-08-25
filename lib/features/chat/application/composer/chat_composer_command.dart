import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/features/settings/application/preferences/chat_defaults_controller.dart';
import 'package:oh_my_llm/features/settings/application/providers/llm_model_configs_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';

import '../../domain/models/chat_conversation.dart';
import '../../domain/models/chat_message.dart';
import '../sessions/chat_sessions_controller.dart';
import 'composer_draft_controller.dart';
import 'template_prompt_compilation_provider.dart';
import 'templated_user_message_builder.dart';

/// 用户点发送/提交编辑时携带的不可变输入。
class ChatComposerSubmitIntent {
  const ChatComposerSubmitIntent({
    required this.conversationId,
    required this.body,
    this.templatePrompt,
    this.variableValues = const {},
    required this.selectedModel,
    this.selectedPresetPrompt,
    required this.reasoningEnabled,
    required this.reasoningEffort,
    this.editingMessageId,
  });

  final String conversationId;
  final String body;
  final TemplatePrompt? templatePrompt;
  final Map<String, String> variableValues;
  final LlmModelConfig? selectedModel;
  final PresetPrompt? selectedPresetPrompt;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;

  /// 非 null 表示编辑既有 user message。
  final String? editingMessageId;
}

/// dispatch 的同步结果：拒绝或已启动。
sealed class ChatComposerDispatchResult {
  const ChatComposerDispatchResult();
}

enum ChatComposerRejectReason {
  empty,
  noModel,
  busy,
  staleConversation,
  invalidTemplate,
  invalidTemplateValue,
}

class ChatComposerRejected extends ChatComposerDispatchResult {
  const ChatComposerRejected(this.reason);
  final ChatComposerRejectReason reason;
}

class ChatComposerAccepted extends ChatComposerDispatchResult {
  const ChatComposerAccepted({required this.completion, required this.wasEdit});

  /// 已启动的 generation Future；dispatch 在它能完成前同步返回。
  final Future<void> completion;
  final bool wasEdit;
}

/// fixed-sequence sendStep 的直接提交输入（无模板/segments 元数据）。
class ChatDirectSubmitIntent {
  const ChatDirectSubmitIntent({
    required this.conversationId,
    required this.content,
    required this.selectedModel,
    this.selectedPresetPrompt,
    required this.reasoningEnabled,
    required this.reasoningEffort,
  });

  final String conversationId;
  final String content;
  final LlmModelConfig? selectedModel;
  final PresetPrompt? selectedPresetPrompt;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;
}

/// composer 的薄编排层：把 Screen 原先两三行的编排收拢，
/// 统一校验、模板拼接、draft 提交语义与 generation facade 调用。
class ChatComposerCommand {
  ChatComposerCommand(this._ref);
  final Ref _ref;

  /// 校验并启动发送/编辑。accepted 返回已启动 completion，不等待其完成。
  ChatComposerDispatchResult dispatch(ChatComposerSubmitIntent intent) {
    final conversation = _ref.read(activeChatConversationProvider);
    if (conversation.id != intent.conversationId) {
      return const ChatComposerRejected(
        ChatComposerRejectReason.staleConversation,
      );
    }
    if (_ref.read(isChatBusyProvider)) {
      return const ChatComposerRejected(ChatComposerRejectReason.busy);
    }
    final model = intent.selectedModel;
    if (model == null) {
      return const ChatComposerRejected(ChatComposerRejectReason.noModel);
    }

    // 选中的模板经唯一编译缓存边界编译一次，与 Screen 共用同一编译结果。
    final templatePrompt = intent.templatePrompt;
    final compilation = templatePrompt == null
        ? null
        : _ref.read(templatePromptCompilationProvider(templatePrompt));
    final buildResult = buildTemplatedUserMessage(
      body: intent.body,
      templatePrompt: templatePrompt,
      compilation: compilation,
      variableValues: intent.variableValues,
    );
    switch (buildResult) {
      case TemplatedUserMessageBuildFailure(:final valueErrors):
        // 编译诊断 -> 模板无效；运行时值错误 -> 值无效。拒绝路径零副作用。
        return ChatComposerRejected(
          valueErrors.isNotEmpty
              ? ChatComposerRejectReason.invalidTemplateValue
              : ChatComposerRejectReason.invalidTemplate,
        );
      case TemplatedUserMessageBuildSuccess(
        :final message,
        :final effectiveVariableValues,
      ):
        if (message.content.trim().isEmpty) {
          return const ChatComposerRejected(ChatComposerRejectReason.empty);
        }

        final editingMessageId = intent.editingMessageId;
        final wasEdit = editingMessageId != null;
        final Future<void> completion;
        if (wasEdit) {
          completion = _ref
              .read(chatSessionsProvider.notifier)
              .editMessage(
                messageId: editingMessageId,
                nextContent: message.content,
                userMessageSegments: message.userMessageSegments,
                templatePromptId: templatePrompt?.id,
                templateVariableValues: effectiveVariableValues,
              );
        } else {
          completion = _ref
              .read(chatSessionsProvider.notifier)
              .sendMessage(
                content: message.content,
                userMessageSegments: message.userMessageSegments,
                modelConfig: model,
                presetPrompt: intent.selectedPresetPrompt,
                reasoningEnabled: intent.reasoningEnabled,
                reasoningEffort: intent.reasoningEffort,
                templatePromptId: templatePrompt?.id,
                templateVariableValues: effectiveVariableValues,
              );
        }

        // accepted 后立即把目标 draft 更新为「body 空、保留本次 template/variables」。
        _ref
            .read(composerDraftProvider.notifier)
            .clearBody(intent.conversationId);
        return ChatComposerAccepted(completion: completion, wasEdit: wasEdit);
    }
  }

  /// fixed-sequence sendStep：直接发送步骤文本，不消费普通 composer draft。
  Future<void> dispatchDirect(ChatDirectSubmitIntent intent) async {
    final conversation = _ref.read(activeChatConversationProvider);
    if (conversation.id != intent.conversationId) return;
    if (_ref.read(isChatBusyProvider)) return;
    final model = intent.selectedModel;
    if (model == null) return;
    final trimmedContent = intent.content.trim();
    if (trimmedContent.isEmpty) return;
    await _ref
        .read(chatSessionsProvider.notifier)
        .sendMessage(
          content: trimmedContent,
          modelConfig: model,
          presetPrompt: intent.selectedPresetPrompt,
          reasoningEnabled: intent.reasoningEnabled,
          reasoningEffort: intent.reasoningEffort,
        );
  }

  // ── composer toolbar 方法 ────────────────────────────────────────────────

  /// 选择模型：更新当前会话并记住为默认。
  void selectModel(String modelId) {
    _ref
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(selectedModelId: modelId);
    _ref.read(chatDefaultsProvider.notifier).rememberModelId(modelId);
  }

  /// 选择 provider：选该 provider 第一个有效模型；无模型时 no-op。
  void selectProvider(String providerId) {
    final providers = _ref.read(llmProviderConfigsProvider);
    final provider = providers.where((p) => p.id == providerId).firstOrNull;
    final targetModelId = provider?.models.firstOrNull?.id;
    if (targetModelId == null) return;
    selectModel(targetModelId);
  }

  /// 选择预设 Prompt：只更新 conversation，不擅自新增 remember-default 行为。
  void selectPreset(String? presetPromptId) {
    _ref
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(
          selectedPresetPromptId: presetPromptId ?? noPresetPromptSelectedId,
        );
  }

  /// 选择模板：只更新目标 conversation 的内存 draft。
  void selectTemplate(String conversationId, String? templatePromptId) {
    _ref
        .read(composerDraftProvider.notifier)
        .selectTemplate(conversationId, templatePromptId);
  }

  void setReasoningEnabled(bool value) {
    _ref
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(reasoningEnabled: value);
  }

  void setReasoningEffort(ReasoningEffort value) {
    _ref
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(reasoningEffort: value);
  }

  void setAutoRetryEnabled(bool value) {
    _ref
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: value);
  }

  /// 调用现有 create command，读取调用后的 active ID，只清该 active draft。
  /// 无消息导致 controller 未新建会话时，仍清当前 active（空输入区）draft。
  Future<void> createConversationAndResetDraft() async {
    await _ref.read(chatSessionsProvider.notifier).createConversation();
    final activeId = _ref.read(activeConversationIdProvider);
    _ref.read(composerDraftProvider.notifier).clearDraft(activeId);
  }
}

/// composer 命令的 provider。
final chatComposerCommandProvider = Provider<ChatComposerCommand>((ref) {
  return ChatComposerCommand(ref);
});

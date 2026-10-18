import 'package:equatable/equatable.dart';
import 'package:oh_my_llm/core/llm/llm_reasoning_effort.dart';
import 'package:oh_my_llm/core/llm/llm_usage_summary.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';

import '../../domain/models/chat_image_attachment.dart';
import '../composer/composer_draft_controller.dart';

/// composer 的不可变显示快照（read-model 层，不含编辑覆盖）。
class ChatWorkspaceComposerReadModel extends Equatable {
  const ChatWorkspaceComposerReadModel({
    required this.modelProviders,
    required this.modelConfigs,
    required this.selectedProviderId,
    required this.selectedModel,
    required this.templatePrompts,
    required this.selectedTemplatePrompt,
    required this.fixedPromptSequences,
    required this.isComposerCollapsed,
    required this.reasoningEnabled,
    required this.reasoningEffort,
    required this.supportsReasoning,
    required this.autoRetryEnabled,
    required this.isBusy,
    required this.isStreaming,
    required this.isAutoRetryWaiting,
    required this.excludedMessageCount,
    required this.usageSummary,
  });

  final List<LlmProviderConfig> modelProviders;
  final List<LlmModelConfig> modelConfigs;
  final String? selectedProviderId;
  final LlmModelConfig? selectedModel;
  final List<TemplatePrompt> templatePrompts;
  final TemplatePrompt? selectedTemplatePrompt;
  final List<FixedPromptSequence> fixedPromptSequences;
  final bool isComposerCollapsed;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;
  final bool supportsReasoning;
  final bool autoRetryEnabled;
  final bool isBusy;
  final bool isStreaming;
  final bool isAutoRetryWaiting;
  final int excludedMessageCount;
  final LlmUsageSummary usageSummary;

  @override
  List<Object?> get props => [
    modelProviders,
    modelConfigs,
    selectedProviderId,
    selectedModel,
    templatePrompts,
    selectedTemplatePrompt,
    fixedPromptSequences,
    isComposerCollapsed,
    reasoningEnabled,
    reasoningEffort,
    supportsReasoning,
    autoRetryEnabled,
    isBusy,
    isStreaming,
    isAutoRetryWaiting,
    excludedMessageCount,
    usageSummary,
  ];
}

/// 交给 composer widget 的 effective composer 状态（可能在编辑时被页面覆盖）。
class ChatWorkspaceComposerState extends Equatable {
  const ChatWorkspaceComposerState({
    required this.readModel,
    required this.selectedTemplatePrompt,
    required this.isEditingMessage,
    this.images = const [],
    this.isImportingImages = false,
    this.imageError,
    this.imageInputBlocked = false,
  });

  final ChatWorkspaceComposerReadModel readModel;
  final TemplatePrompt? selectedTemplatePrompt;
  final bool isEditingMessage;
  final List<ChatImageAttachment> images;
  final bool isImportingImages;
  final String? imageError;
  final bool imageInputBlocked;

  factory ChatWorkspaceComposerState.compose({
    required ChatWorkspaceComposerReadModel readModel,
    required ComposerDraft editingDraft,
    required bool isEditingMessage,
    required List<TemplatePrompt> templatePrompts,
    List<ChatImageAttachment> images = const [],
    bool isImportingImages = false,
    String? imageError,
    bool imageInputBlocked = false,
  }) {
    final editingTemplateId = editingDraft.selectedTemplatePromptId;
    final selectedTemplatePrompt = isEditingMessage
        ? (editingTemplateId == null
              ? null
              : templatePrompts
                    .where((template) => template.id == editingTemplateId)
                    .firstOrNull)
        : readModel.selectedTemplatePrompt;
    return ChatWorkspaceComposerState(
      readModel: readModel,
      // 编辑无模板消息时最终选择必须为 null，不能回退到会话模板。
      selectedTemplatePrompt: selectedTemplatePrompt,
      isEditingMessage: isEditingMessage,
      images: List.unmodifiable(images),
      isImportingImages: isImportingImages,
      imageError: imageError,
      imageInputBlocked: imageInputBlocked,
    );
  }

  @override
  List<Object?> get props => [
    readModel,
    selectedTemplatePrompt,
    isEditingMessage,
    images,
    isImportingImages,
    imageError,
    imageInputBlocked,
  ];
}

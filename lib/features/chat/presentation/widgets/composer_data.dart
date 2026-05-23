import 'package:flutter/material.dart';

import '../../domain/models/chat_message.dart';
import '../../../settings/domain/models/llm_model_config.dart';
import '../../../settings/domain/models/llm_provider_config.dart';
import '../../../settings/domain/models/prompt_template.dart';
import '../../../settings/domain/models/template_prompt.dart';

class ComposerData {
  const ComposerData({
    required this.hasModels,
    required this.modelProviders,
    required this.modelConfigs,
    required this.selectedProviderId,
    required this.selectedModel,
    required this.promptTemplates,
    required this.selectedPromptTemplate,
    required this.templatePrompts,
    required this.selectedTemplatePrompt,
    required this.templateVariableControllers,
    required this.isComposerCollapsed,
    required this.reasoningEnabled,
    required this.reasoningEffort,
    required this.supportsReasoning,
    required this.autoRetryEnabled,
    required this.isBusy,
    required this.isStreaming,
    required this.excludedMessageCount,
  });

  final bool hasModels;
  final List<LlmProviderConfig> modelProviders;
  final List<LlmModelConfig> modelConfigs;
  final String? selectedProviderId;
  final LlmModelConfig? selectedModel;
  final List<PromptTemplate> promptTemplates;
  final PromptTemplate? selectedPromptTemplate;
  final List<TemplatePrompt> templatePrompts;
  final TemplatePrompt? selectedTemplatePrompt;
  final Map<String, TextEditingController> templateVariableControllers;
  final bool isComposerCollapsed;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;
  final bool supportsReasoning;
  final bool autoRetryEnabled;
  final bool isBusy;
  final bool isStreaming;
  final int excludedMessageCount;
}

class ComposerCallbacks {
  const ComposerCallbacks({
    required this.onProviderSelected,
    required this.onModelSelected,
    required this.onPromptTemplateSelected,
    required this.onTemplatePromptSelected,
    required this.onToggleComposerCollapsed,
    this.onReasoningEnabledChanged,
    this.onReasoningEffortChanged,
    this.onAutoRetryEnabledChanged,
    required this.onOpenFixedPromptSequenceRunner,
    required this.onOpenMessageFilter,
    this.onSendPressed,
    this.onStopStreaming,
  });

  final ValueChanged<String> onProviderSelected;
  final ValueChanged<String> onModelSelected;
  final ValueChanged<String?> onPromptTemplateSelected;
  final ValueChanged<String?> onTemplatePromptSelected;
  final VoidCallback onToggleComposerCollapsed;
  final ValueChanged<bool>? onReasoningEnabledChanged;
  final ValueChanged<ReasoningEffort>? onReasoningEffortChanged;
  final ValueChanged<bool>? onAutoRetryEnabledChanged;
  final Future<void> Function() onOpenFixedPromptSequenceRunner;
  final Future<void> Function() onOpenMessageFilter;
  final Future<void> Function()? onSendPressed;
  final Future<void> Function()? onStopStreaming;
}

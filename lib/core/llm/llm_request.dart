import 'package:equatable/equatable.dart';

import 'llm_api_protocol.dart';
import 'llm_content.dart';
import 'llm_event.dart';
import 'llm_reasoning_effort.dart';

class LlmRequestTarget extends Equatable {
  const LlmRequestTarget({
    required this.protocol,
    required this.endpoint,
    required this.apiKey,
    required this.model,
  });
  final LlmApiProtocol protocol;
  final String endpoint;
  final String apiKey;
  final String model;
  @override
  List<Object?> get props => [protocol, endpoint, apiKey, model];
}

class LlmRequest extends Equatable {
  LlmRequest({
    required this.target,
    required List<LlmInputItem> input,
    this.options = const LlmGenerationOptions(),
    List<LlmToolDefinition> tools = const [],
    this.toolChoice = const LlmToolChoice.auto(),
    this.parallelToolCalls,
  }) : input = List.unmodifiable(input),
       tools = List.unmodifiable(tools);
  final LlmRequestTarget target;
  final List<LlmInputItem> input;
  final LlmGenerationOptions options;
  final List<LlmToolDefinition> tools;
  final LlmToolChoice toolChoice;
  final bool? parallelToolCalls;
  @override
  List<Object?> get props => [
    target,
    input,
    options,
    tools,
    toolChoice,
    parallelToolCalls,
  ];
  bool get hasNativeContext =>
      tools.isNotEmpty ||
      input.any((item) => item is LlmAssistantTurn || item is LlmToolResult);
}

class LlmToolDefinition extends Equatable {
  LlmToolDefinition({
    required this.name,
    required this.description,
    required Map<String, Object?> parameters,
  }) : parameters = immutableLlmJson(parameters) as Map<String, Object?> {
    if (name.trim().isEmpty || this.parameters['type'] != 'object') {
      throw const LlmException(
        '工具必须有名称和 object schema',
        kind: LlmFailureKind.invalidRequest,
      );
    }
  }
  final String name;
  final String description;
  final Map<String, Object?> parameters;
  @override
  List<Object?> get props => [name, description, parameters];
}

enum LlmToolChoiceKind { auto, none, required, named }

class LlmToolChoice extends Equatable {
  const LlmToolChoice.auto() : kind = LlmToolChoiceKind.auto, name = null;
  const LlmToolChoice.none() : kind = LlmToolChoiceKind.none, name = null;
  const LlmToolChoice.required()
    : kind = LlmToolChoiceKind.required,
      name = null;
  const LlmToolChoice.named(this.name) : kind = LlmToolChoiceKind.named;
  final LlmToolChoiceKind kind;
  final String? name;
  @override
  List<Object?> get props => [kind, name];
}

class LlmGenerationOptions extends Equatable {
  const LlmGenerationOptions({
    this.reasoningEffort,
    this.maxOutputTokens,
    this.responseHeaderTimeout,
    this.streamIdleTimeout,
    this.protocolOptions,
  });
  final ReasoningEffort? reasoningEffort;
  final int? maxOutputTokens;
  final Duration? responseHeaderTimeout;
  final Duration? streamIdleTimeout;
  final LlmProtocolOptions? protocolOptions;
  @override
  List<Object?> get props => [
    reasoningEffort,
    maxOutputTokens,
    responseHeaderTimeout,
    streamIdleTimeout,
    protocolOptions,
  ];
}

sealed class LlmProtocolOptions extends Equatable {
  const LlmProtocolOptions();
}

final class ResponsesOptions extends LlmProtocolOptions {
  const ResponsesOptions({
    this.reasoningSummary,
    this.reasoningContext,
    this.promptCacheKey,
  });
  final ResponsesReasoningSummary? reasoningSummary;
  final ResponsesReasoningContext? reasoningContext;
  final String? promptCacheKey;
  @override
  List<Object?> get props => [
    reasoningSummary,
    reasoningContext,
    promptCacheKey,
  ];
}

enum ResponsesReasoningSummary { auto }

enum ResponsesReasoningContext { currentTurn }

final class MessagesOptions extends LlmProtocolOptions {
  const MessagesOptions({this.automaticCacheControl = false, this.cacheTtl});
  final bool automaticCacheControl;
  final MessagesCacheTtl? cacheTtl;
  @override
  List<Object?> get props => [automaticCacheControl, cacheTtl];
}

enum MessagesCacheTtl { fiveMinutes, oneHour }

final class ChatCompletionsOptions extends LlmProtocolOptions {
  const ChatCompletionsOptions({this.promptCacheKey});
  final String? promptCacheKey;
  @override
  List<Object?> get props => [promptCacheKey];
}

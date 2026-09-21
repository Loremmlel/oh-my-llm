import 'package:equatable/equatable.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';

/// 可持久化的请求审计信息，不包含运行时 target 中的凭据。
class AgentRunRequestSnapshot extends Equatable {
  AgentRunRequestSnapshot({
    this.modelId,
    this.modelLabel = '',
    List<LlmToolDefinition> tools = const [],
    List<LlmInputItem>? inputHistory,
  }) : tools = List.unmodifiable(tools),
       inputHistory = inputHistory == null
           ? null
           : List.unmodifiable(inputHistory);

  final String? modelId;
  final String modelLabel;
  final List<LlmToolDefinition> tools;

  /// 保存实际输入以便撤回后查看；旧记录未保存时为空。
  final List<LlmInputItem>? inputHistory;

  AgentRunRequestSnapshot copyWith({List<LlmInputItem>? inputHistory}) =>
      AgentRunRequestSnapshot(
        modelId: modelId,
        modelLabel: modelLabel,
        tools: tools,
        inputHistory: inputHistory ?? this.inputHistory,
      );

  @override
  List<Object?> get props => [modelId, modelLabel, tools, inputHistory];
}

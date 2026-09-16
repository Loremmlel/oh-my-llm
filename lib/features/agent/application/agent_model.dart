import 'package:oh_my_llm/core/llm/llm_request.dart';

// 主任务和所有子职责共用长思考预算，避免生产装配与运行器默认值分叉。
const agentDefaultGenerationOptions = LlmGenerationOptions(
  maxOutputTokens: 65536,
  responseHeaderTimeout: Duration(minutes: 10),
  streamIdleTimeout: Duration(minutes: 10),
);

class AgentModel {
  const AgentModel({
    required this.id,
    required this.label,
    required this.target,
    required this.options,
  });
  final String id, label;
  final LlmRequestTarget target;
  final LlmGenerationOptions options;
}

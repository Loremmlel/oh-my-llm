import 'package:oh_my_llm/core/llm/llm_request.dart';

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

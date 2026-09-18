import 'llm_content.dart';
import 'llm_endpoint_resolver.dart';
import 'llm_request.dart';

/// 显式切换目标时剥离原生附加数据，仅保留公共文本与函数工具。
/// 同一目标仍原样重放；转换保持历史项数量，避免改变调用和压缩边界。
List<LlmInputItem> convertLlmHistory(
  List<LlmInputItem> history,
  LlmRequestTarget target,
) {
  final endpoint = const LlmEndpointResolver().resolveGenerationEndpoint(
    rawUrl: target.endpoint,
    protocol: target.protocol,
  );
  final occupied = history
      .whereType<LlmAssistantTurn>()
      .expand((turn) => turn.toolCalls)
      .map((call) => call.callId)
      .toSet();
  final ids = <String, String>{};
  var serial = 0;
  String convertedId(String original) => ids.putIfAbsent(original, () {
    String id;
    do {
      id = 'omll_${serial++}';
    } while (!occupied.add(id));
    return id;
  });
  return [
    for (final item in history)
      switch (item) {
        LlmAssistantTurn(replay: final replay?)
            when replay.protocol != target.protocol ||
                replay.endpoint != endpoint ||
                replay.model != target.model =>
          _portableTurn(item, convertedId),
        LlmToolResult() when ids.containsKey(item.callId) => LlmToolResult(
          callId: ids[item.callId]!,
          name: item.name,
          output: item.output,
          isError: item.isError,
        ),
        _ => item,
      },
  ];
}

LlmAssistantTurn _portableTurn(
  LlmAssistantTurn turn,
  String Function(String) convertId,
) => LlmAssistantTurn.portable(
  text: turn.text,
  toolCalls: [
    for (final call in turn.toolCalls)
      LlmToolCall(
        callId: convertId(call.callId),
        name: call.name,
        argumentsJson: call.argumentsJson,
      ),
  ],
);

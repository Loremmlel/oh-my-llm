import 'llm_api_protocol.dart';
import 'llm_content.dart';
import 'llm_endpoint_resolver.dart';
import 'llm_request.dart';

/// 显式切换目标时只迁移公共文本与函数工具，不猜补厂商推理或内置工具。
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
        LlmAssistantTurn()
            when item.replay.protocol != target.protocol ||
                item.replay.endpoint != endpoint ||
                item.replay.model != target.model =>
          _convertTurn(item, target, endpoint, convertedId),
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

LlmAssistantTurn _convertTurn(
  LlmAssistantTurn turn,
  LlmRequestTarget target,
  Uri endpoint,
  String Function(String) convertId,
) {
  final calls = [
    for (final call in turn.toolCalls)
      LlmToolCall(
        callId: convertId(call.callId),
        name: call.name,
        argumentsJson: call.argumentsJson,
      ),
  ];
  final List<Map<String, Object?>> items = switch (target.protocol) {
    LlmApiProtocol.chatCompletions => [
      {
        'role': 'assistant',
        'content': turn.text,
        if (calls.isNotEmpty)
          'tool_calls': [
            for (final call in calls)
              {
                'id': call.callId,
                'type': 'function',
                'function': {
                  'name': call.name,
                  'arguments': call.argumentsJson,
                },
              },
          ],
      },
    ],
    LlmApiProtocol.responses => [
      if (turn.text.isNotEmpty || calls.isEmpty)
        {
          'type': 'message',
          'role': 'assistant',
          'content': [
            {
              'type': 'output_text',
              'text': turn.text,
              'annotations': <Object?>[],
            },
          ],
        },
      for (final call in calls)
        {
          'type': 'function_call',
          'call_id': call.callId,
          'name': call.name,
          'arguments': call.argumentsJson,
        },
    ],
    LlmApiProtocol.anthropic => [
      if (turn.text.isNotEmpty || calls.isEmpty)
        {'type': 'text', 'text': turn.text},
      for (final call in calls)
        {
          'type': 'tool_use',
          'id': call.callId,
          'name': call.name,
          'input': call.arguments,
        },
    ],
  };
  return LlmAssistantTurn(
    text: turn.text,
    toolCalls: calls,
    replay: LlmReplayEnvelope(
      protocol: target.protocol,
      endpoint: endpoint,
      model: target.model,
      items: items,
    ),
  );
}

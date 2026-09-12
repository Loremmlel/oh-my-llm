import 'dart:async';
import 'dart:convert';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_call_control.dart';
import 'package:oh_my_llm/core/llm/llm_client.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';

const agentTestTarget = LlmRequestTarget(
  protocol: LlmApiProtocol.chatCompletions,
  endpoint: 'https://example.com/v1/chat/completions',
  apiKey: 'test-key-not-for-storage',
  model: 'test',
);

class StreamingAgentClient extends LlmClient {
  StreamingAgentClient(this.respond);
  final Stream<LlmEvent> Function(LlmRequest request, int index) respond;
  int _index = 0;
  @override
  Stream<LlmEvent> generate(LlmRequest request, LlmCallControl control) =>
      respond(request, _index++);
}

class FakeAgentClient extends LlmClient {
  FakeAgentClient(this.respond);
  final FutureOr<LlmResult> Function(LlmRequest request, int index) respond;
  final requests = <LlmRequest>[];
  final controls = <LlmCallControl>[];
  @override
  Stream<LlmEvent> generate(LlmRequest request, LlmCallControl control) async* {
    requests.add(request);
    controls.add(control);
    final result = await respond(request, requests.length - 1);
    yield LlmEvent(contentDelta: result.content, usage: result.usage);
    yield LlmCompleted(result);
  }
}

LlmToolCall agentCall(String id, String name, Map<String, Object?> arguments) =>
    LlmToolCall(callId: id, name: name, argumentsJson: jsonEncode(arguments));

LlmResult agentReply({
  String text = '完成',
  List<LlmToolCall> calls = const [],
  LlmStopKind? stopKind,
  LlmUsage? usage,
}) => LlmResult(
  content: calls.isEmpty ? text : '',
  stopKind:
      stopKind ??
      (calls.isEmpty ? LlmStopKind.completed : LlmStopKind.toolCalls),
  usage: usage,
  assistantTurn: LlmAssistantTurn(
    text: calls.isEmpty ? text : '',
    toolCalls: calls,
    replay: LlmReplayEnvelope(
      protocol: agentTestTarget.protocol,
      endpoint: Uri.parse(agentTestTarget.endpoint),
      model: agentTestTarget.model,
      items: [
        {
          'role': 'assistant',
          'content': calls.isEmpty ? text : '',
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
    ),
  ),
);

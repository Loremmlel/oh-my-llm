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
  String reasoning = '',
  LlmRequestTarget target = agentTestTarget,
  List<LlmToolCall> calls = const [],
  LlmStopKind? stopKind,
  LlmUsage? usage,
}) => LlmResult(
  content: calls.isEmpty ? text : '',
  reasoningContent: reasoning,
  stopKind:
      stopKind ??
      (calls.isEmpty ? LlmStopKind.completed : LlmStopKind.toolCalls),
  usage: usage,
  assistantTurn: LlmAssistantTurn(
    text: calls.isEmpty ? text : '',
    toolCalls: calls,
    replay: LlmReplayEnvelope(
      protocol: target.protocol,
      endpoint: Uri.parse(target.endpoint),
      model: target.model,
      items: [
        {
          'role': 'assistant',
          'content': calls.isEmpty ? text : '',
          if (reasoning.isNotEmpty) 'reasoning_content': reasoning,
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

/// 旧状态测试仍关注状态生命周期；补上交付前真实执行的审查往返。
FakeAgentClient reviewedAgentClient(
  FutureOr<LlmResult> Function(LlmRequest, int) respond,
) {
  var index = 0;
  return FakeAgentClient((request, _) async {
    if (request.tools.any((t) => t.name == 'submit_review')) {
      return agentReply(
        target: request.target,
        calls: [
          agentCall('verdict', 'submit_review', {
            'approved': true,
            'feedback': '通过',
          }),
        ],
      );
    }
    final result = await respond(request, index++);
    final calls = result.assistantTurn?.toolCalls ?? [];
    if (!calls.any((c) => c.name == 'update_story_state')) return result;
    return agentReply(
      target: request.target,
      calls: [
        for (final call in calls) ...[
          if (call.name == 'update_story_state')
            agentCall('review-${call.callId}', 'review_document', {
              'name': call.arguments['name'],
              'task': '核对当前稿件',
            }),
          call,
        ],
      ],
    );
  });
}

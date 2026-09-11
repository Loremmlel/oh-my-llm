import 'dart:convert';

import '../llm_api_protocol.dart';
import '../llm_content.dart';
import '../llm_event.dart';
import '../llm_request.dart';

Never _invalid(String message) =>
    throw LlmException(message, kind: LlmFailureKind.invalidRequest);

/// 仅编码已完成的 assistant turn，不让原生 envelope 成为请求根字段注入入口。
Map<String, Object> encodeLlmInput(LlmRequest request, Uri endpoint) {
  final names = request.tools.map((tool) => tool.name).toSet();
  if (names.length != request.tools.length) _invalid('工具名称重复');
  if (request.toolChoice.kind == LlmToolChoiceKind.named &&
      !names.contains(request.toolChoice.name)) {
    _invalid('指定工具未定义');
  }
  if (request.toolChoice.kind == LlmToolChoiceKind.required && names.isEmpty) {
    _invalid('required 必须声明工具');
  }
  final options = request.options;
  if ((options.maxOutputTokens != null && options.maxOutputTokens! <= 0) ||
      (options.responseHeaderTimeout != null &&
          options.responseHeaderTimeout! <= Duration.zero) ||
      (options.streamIdleTimeout != null &&
          options.streamIdleTimeout! <= Duration.zero)) {
    _invalid('生成上限和超时必须为正');
  }
  final pending = <String, String>{};
  final seen = <String>{};
  final encoded = <Map<String, Object?>>[];
  final system = <String>[];
  final protocol = request.target.protocol;
  for (final item in request.input) {
    if (item is! LlmToolResult && pending.isNotEmpty) _invalid('工具结果尚未完整提交');
    switch (item) {
      case LlmTextMessage():
        if (protocol == LlmApiProtocol.anthropic &&
            item.role == LlmRole.system) {
          if (encoded.isNotEmpty) _invalid('Messages 不支持中段 system 消息');
          system.add(item.text);
        } else if (protocol == LlmApiProtocol.anthropic &&
            item.role == LlmRole.user &&
            encoded.isNotEmpty &&
            encoded.last['role'] == 'user' &&
            encoded.last['content'] is List) {
          (encoded.last['content'] as List).add({
            'type': 'text',
            'text': item.text,
          });
        } else {
          encoded.add({'role': item.role.name, 'content': item.text});
        }
      case LlmAssistantTurn():
        final replay = item.replay;
        if (replay.protocol != protocol ||
            replay.endpoint != endpoint ||
            replay.model != request.target.model) {
          _invalid('原生续接不能跨协议、端点或模型');
        }
        if (item.toolCalls.length > maxLlmToolCalls) _invalid('工具调用数量超过限制');
        final nativeCalls = <String, LlmToolCall>{};
        if (replay.items.isEmpty) _invalid('缺少可续接的原生输出');
        final nativeItems = [
          for (final native in replay.items)
            _replayItem(native, protocol, nativeCalls),
        ];
        if (protocol == LlmApiProtocol.anthropic) {
          // Messages 的多个内容块属于同一条 assistant 消息。
          encoded.add({'role': 'assistant', 'content': nativeItems});
        } else {
          encoded.addAll(nativeItems);
        }
        for (final call in item.toolCalls) {
          final nativeCall = nativeCalls.remove(call.callId);
          if (!seen.add(call.callId) ||
              nativeCall == null ||
              nativeCall.name != call.name ||
              nativeCall != call) {
            _invalid('工具调用 ID、名称或参数与原生内容不一致');
          }
          pending[call.callId] = call.name;
        }
        if (nativeCalls.isNotEmpty) _invalid('原生内容有未声明的工具调用');
      case LlmToolResult():
        if (pending.remove(item.callId) != item.name) {
          _invalid('工具结果缺失、重复或名称不匹配');
        }
        final output = item.isError
            ? jsonEncode({'is_error': true, 'content': item.output})
            : item.output;
        switch (protocol) {
          case LlmApiProtocol.chatCompletions:
            encoded.add({
              'role': 'tool',
              'tool_call_id': item.callId,
              'content': output,
            });
          case LlmApiProtocol.responses:
            encoded.add({
              'type': 'function_call_output',
              'call_id': item.callId,
              'output': output,
            });
          case LlmApiProtocol.anthropic:
            final block = {
              'type': 'tool_result',
              'tool_use_id': item.callId,
              'content': item.output,
              'is_error': item.isError,
            };
            if (encoded.isNotEmpty &&
                encoded.last['role'] == 'user' &&
                encoded.last['content'] is List) {
              (encoded.last['content'] as List).add(block);
            } else {
              encoded.add({
                'role': 'user',
                'content': <Object?>[block],
              });
            }
        }
    }
  }
  if (pending.isNotEmpty) _invalid('工具结果尚未完整提交');
  return {
    if (system.isNotEmpty) 'system': system.join('\n'),
    protocol == LlmApiProtocol.responses ? 'input' : 'messages': encoded,
  };
}

Map<String, Object?> _replayItem(
  Map<String, Object?> item,
  LlmApiProtocol protocol,
  Map<String, LlmToolCall> calls,
) {
  Map<String, Object?> pick(List<String> keys) => {
    for (final key in keys)
      if (item.containsKey(key)) key: item[key],
  };
  void call(Object? id, Object? name, Object? arguments) {
    if (id is! String ||
        name is! String ||
        id.isEmpty ||
        name.isEmpty ||
        calls.containsKey(id)) {
      _invalid('原生工具调用缺少唯一 ID 或名称');
    }
    if (arguments is! String) _invalid('原生工具参数必须为 JSON 字符串');
    try {
      calls[id] = LlmToolCall(callId: id, name: name, argumentsJson: arguments);
    } on LlmException {
      _invalid('原生工具参数必须为完整 JSON object');
    }
  }

  switch (protocol) {
    case LlmApiProtocol.chatCompletions:
      if (item['role'] != 'assistant') _invalid('续接消息必须是 assistant');
      final tools = item['tool_calls'];
      if (tools != null) {
        if (tools is! List) _invalid('tool_calls 必须为数组');
        for (final tool in tools) {
          if (tool is! Map ||
              tool['type'] != 'function' ||
              tool['function'] is! Map) {
            _invalid('只支持 function 工具');
          }
          final function = tool['function'] as Map;
          call(tool['id'], function['name'], function['arguments']);
        }
      }
      return pick(['role', 'content', 'tool_calls', 'reasoning_content']);
    case LlmApiProtocol.responses:
      switch (item['type']) {
        case 'function_call':
          call(item['call_id'], item['name'], item['arguments']);
          return pick(['type', 'id', 'call_id', 'name', 'arguments', 'status']);
        case 'reasoning':
          return pick([
            'type',
            'id',
            'summary',
            'content',
            'encrypted_content',
            'status',
          ]);
        case 'message':
          if (item['role'] != 'assistant') _invalid('续接消息必须是 assistant');
          return pick(['type', 'id', 'role', 'content', 'status']);
        default:
          _invalid('不支持的 Responses 续接内容');
      }
    case LlmApiProtocol.anthropic:
      switch (item['type']) {
        case 'tool_use':
          call(item['id'], item['name'], jsonEncode(item['input']));
          return pick(['type', 'id', 'name', 'input']);
        case 'text':
          return pick(['type', 'text']);
        case 'thinking':
          if (item['signature'] is! String ||
              (item['signature'] as String).isEmpty) {
            _invalid('thinking 续接缺少签名');
          }
          return pick(['type', 'thinking', 'signature']);
        case 'redacted_thinking':
          return pick(['type', 'data']);
        default:
          _invalid('不支持的 Messages 续接内容');
      }
  }
}

Map<String, Object> encodeLlmTools(LlmRequest request) {
  if (request.tools.isEmpty) return {};
  final protocol = request.target.protocol;
  final definitions = [
    for (final tool in request.tools)
      switch (protocol) {
        LlmApiProtocol.chatCompletions => {
          'type': 'function',
          'function': {
            'name': tool.name,
            'description': tool.description,
            'parameters': tool.parameters,
            'strict': false,
          },
        },
        LlmApiProtocol.responses => {
          'type': 'function',
          'name': tool.name,
          'description': tool.description,
          'parameters': tool.parameters,
          'strict': false,
        },
        LlmApiProtocol.anthropic => {
          'name': tool.name,
          'description': tool.description,
          'input_schema': tool.parameters,
        },
      },
  ];
  final choice = request.toolChoice;
  final Object wireChoice;
  if (protocol == LlmApiProtocol.anthropic) {
    wireChoice = {
      'type': switch (choice.kind) {
        LlmToolChoiceKind.required => 'any',
        LlmToolChoiceKind.named => 'tool',
        _ => choice.kind.name,
      },
      if (choice.kind == LlmToolChoiceKind.named) 'name': choice.name!,
      if (choice.kind != LlmToolChoiceKind.none &&
          request.parallelToolCalls != null)
        'disable_parallel_tool_use': !request.parallelToolCalls!,
    };
  } else if (choice.kind == LlmToolChoiceKind.named) {
    wireChoice = protocol == LlmApiProtocol.chatCompletions
        ? {
            'type': 'function',
            'function': {'name': choice.name!},
          }
        : {'type': 'function', 'name': choice.name!};
  } else {
    wireChoice = choice.kind.name;
  }
  return {
    'tools': definitions,
    'tool_choice': wireChoice,
    if (protocol != LlmApiProtocol.anthropic &&
        request.parallelToolCalls != null)
      'parallel_tool_calls': request.parallelToolCalls!,
  };
}

Map<String, Object> encodeLlmOptions(LlmRequest request) {
  final protocol = request.target.protocol;
  final options = request.options;
  final specific = options.protocolOptions;
  final result = <String, Object>{};
  if (options.maxOutputTokens case final limit?) {
    result[switch (protocol) {
          LlmApiProtocol.chatCompletions => 'max_completion_tokens',
          LlmApiProtocol.responses => 'max_output_tokens',
          LlmApiProtocol.anthropic => 'max_tokens',
        }] =
        limit;
  }
  switch (specific) {
    case ChatCompletionsOptions():
      if (protocol != LlmApiProtocol.chatCompletions) {
        _invalid('Chat Completions 选项不能用于其他协议');
      }
      if (specific.promptCacheKey case final key?) {
        result['prompt_cache_key'] = key;
      }
    case ResponsesOptions():
      if (protocol != LlmApiProtocol.responses) {
        _invalid('Responses 选项不能用于其他协议');
      }
      if (specific.promptCacheKey case final key?) {
        result['prompt_cache_key'] = key;
      }
    case MessagesOptions():
      if (protocol != LlmApiProtocol.anthropic) _invalid('Messages 选项不能用于其他协议');
      if (specific.cacheTtl != null && !specific.automaticCacheControl) {
        _invalid('缓存 TTL 必须启用自动缓存');
      }
      if (specific.automaticCacheControl) {
        result['cache_control'] = {
          'type': 'ephemeral',
          if (specific.cacheTtl != null)
            'ttl': specific.cacheTtl == MessagesCacheTtl.oneHour ? '1h' : '5m',
        };
      }
    case null:
      break;
  }
  return result;
}

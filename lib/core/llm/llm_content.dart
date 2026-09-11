import 'dart:collection';
import 'dart:convert';

import 'package:equatable/equatable.dart';

import 'llm_api_protocol.dart';
import 'llm_event.dart';

enum LlmRole { system, user, assistant }

sealed class LlmInputItem extends Equatable {
  const LlmInputItem();
}

class LlmTextMessage extends LlmInputItem {
  const LlmTextMessage({required this.role, required this.text});
  final LlmRole role;
  final String text;
  @override
  List<Object?> get props => [role, text];
}

const maxLlmToolCalls = 32;
const maxLlmToolBytes = 1024 * 1024;

/// JSON 边界同时验证可序列化性并深复制，禁止外部修改嵌套 schema 或回放内容。
Object? immutableLlmJson(Object? value) {
  final visiting = HashSet<Object>.identity();
  Object? freeze(Object? value) {
    if (value == null ||
        value is String ||
        value is bool ||
        (value is num && value.isFinite)) {
      return value;
    }
    if (value is! Map && value is! List) throw const FormatException();
    if (!visiting.add(value)) throw const FormatException();
    try {
      if (value is List) return List<Object?>.unmodifiable(value.map(freeze));
      final map = value as Map;
      return Map<String, Object?>.unmodifiable(
        map.map((key, value) {
          if (key is! String) throw const FormatException();
          return MapEntry(key, freeze(value));
        }),
      );
    } finally {
      visiting.remove(value);
    }
  }

  try {
    return freeze(value);
  } on FormatException {
    throw const LlmException(
      '内容必须为无循环的 JSON 值',
      kind: LlmFailureKind.invalidRequest,
    );
  }
}

class LlmToolCall extends Equatable {
  LlmToolCall({
    required this.callId,
    required this.name,
    required this.argumentsJson,
  }) : arguments = _arguments(argumentsJson) {
    if (callId.trim().isEmpty || name.trim().isEmpty) {
      throw const LlmException('工具调用缺少 ID 或名称');
    }
  }
  final String callId;
  final String name;
  final String argumentsJson;
  final Map<String, Object?> arguments;
  @override
  List<Object?> get props => [callId, name, arguments];

  static Map<String, Object?> _arguments(String text) {
    if (utf8.encode(text).length > maxLlmToolBytes) {
      throw const LlmException('工具参数超过大小限制');
    }
    try {
      final value = jsonDecode(text);
      if (value is! Map) throw const FormatException();
      return immutableLlmJson(value) as Map<String, Object?>;
    } catch (_) {
      throw const LlmException('工具参数必须为完整 JSON object');
    }
  }
}

class LlmToolResult extends LlmInputItem {
  LlmToolResult({
    required this.callId,
    required this.name,
    required this.output,
    this.isError = false,
  }) {
    if (utf8.encode(output).length > maxLlmToolBytes) {
      throw const LlmException(
        '工具结果超过大小限制',
        kind: LlmFailureKind.invalidRequest,
      );
    }
  }
  final String callId;
  final String name;
  final String output;
  final bool isError;
  @override
  List<Object?> get props => [callId, name, output, isError];
}

class LlmReplayEnvelope extends Equatable {
  LlmReplayEnvelope({
    required this.protocol,
    required this.endpoint,
    required this.model,
    required List<Map<String, Object?>> items,
  }) : items = List.unmodifiable(
         items.map((item) => immutableLlmJson(item) as Map<String, Object?>),
       );
  final LlmApiProtocol protocol;
  final Uri endpoint;
  final String model;
  final List<Map<String, Object?>> items;
  @override
  List<Object?> get props => [protocol, endpoint, model, items];
}

class LlmAssistantTurn extends LlmInputItem {
  LlmAssistantTurn({
    required this.replay,
    this.text = '',
    this.reasoning = '',
    List<LlmToolCall> toolCalls = const [],
  }) : toolCalls = List.unmodifiable(toolCalls);
  final LlmReplayEnvelope replay;
  final String text;
  final String reasoning;
  final List<LlmToolCall> toolCalls;
  @override
  List<Object?> get props => [replay, text, reasoning, toolCalls];
}

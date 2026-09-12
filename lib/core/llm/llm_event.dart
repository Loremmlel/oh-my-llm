import 'package:equatable/equatable.dart';

import 'llm_api_protocol.dart';
import 'llm_content.dart';
import 'llm_usage.dart';

enum LlmFailureKind {
  transport,
  cancelled,
  timeout,
  invalidRequest,
  invalidResponse,
  unsupported,
}

class LlmException implements Exception {
  const LlmException(
    this.message, {
    this.protocol,
    this.uri,
    this.statusCode,
    this.apiErrorCode,
    this.responseBody,
    this.usage,
    this.cause,
    this.causeStackTrace,
    this.kind = LlmFailureKind.invalidResponse,
    this.requestId,
  });

  final String message;
  final LlmFailureKind kind;
  final String? requestId;

  /// 请求目标协议（发生时可识别时填充）。
  final LlmApiProtocol? protocol;

  /// 请求目标 URI（URL 解析成功后可识别时填充）。
  final Uri? uri;

  /// HTTP 状态码（非 2xx 响应时可用）。
  final int? statusCode;

  /// 厂商错误码（从官方错误 envelope 提取）。
  final String? apiErrorCode;

  /// 原始响应体（HTTP 错误或 SSE 解析失败时的原文）。
  final String? responseBody;

  /// 失败终态自然携带的 Token 用量。
  final LlmUsage? usage;

  /// 被包装的源异常（连接中断、TLS 握手失败等）。
  final Object? cause;

  /// 源异常对应的堆栈。
  final StackTrace? causeStackTrace;

  @override
  String toString() => message;
}

/// 单次模型调用的增量；只有完整终态可以用于续接。
class LlmEvent extends Equatable {
  const LlmEvent({
    this.contentDelta = '',
    this.reasoningDelta = '',
    this.finishReason,
    this.usage,
  });
  final String contentDelta;
  final String reasoningDelta;
  final String? finishReason;
  final LlmUsage? usage;
  @override
  List<Object?> get props => [
    contentDelta,
    reasoningDelta,
    finishReason,
    usage,
  ];
  bool get isEmpty => contentDelta.isEmpty && reasoningDelta.isEmpty;
}

enum LlmStopKind { completed, toolCalls, incomplete, refused, unknown }

class LlmResult extends Equatable {
  const LlmResult({
    this.content = '',
    this.reasoningContent = '',
    this.finishReason,
    this.usage,
    this.stopKind = LlmStopKind.unknown,
    this.diagnosticBody,
    this.assistantTurn,
    this.requestId,
  });
  final String content;
  final String reasoningContent;
  final String? finishReason;
  final LlmUsage? usage;
  final LlmStopKind stopKind;
  final String? diagnosticBody;
  final LlmAssistantTurn? assistantTurn;
  final String? requestId;
  @override
  List<Object?> get props => [
    content,
    reasoningContent,
    finishReason,
    usage,
    stopKind,
    diagnosticBody,
    assistantTurn,
    requestId,
  ];
  List<LlmToolCall> get toolCalls => assistantTurn?.toolCalls ?? const [];
}

final class LlmToolArgumentsDelta extends LlmEvent {
  const LlmToolArgumentsDelta({
    required this.index,
    required this.argumentsDelta,
    this.callId,
    this.name,
  });
  final int index;
  final String argumentsDelta;
  final String? callId;
  final String? name;
  @override
  List<Object?> get props => [
    ...super.props,
    index,
    argumentsDelta,
    callId,
    name,
  ];
}

final class LlmCompleted extends LlmEvent {
  LlmCompleted(this.result)
    : super(finishReason: result.finishReason, usage: result.usage);
  final LlmResult result;
  @override
  List<Object?> get props => [result];
}

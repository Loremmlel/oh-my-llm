import 'dart:async';

import 'llm_call_control.dart';
import 'llm_endpoint_resolver.dart';
import 'llm_event.dart';
import 'llm_request.dart';
import 'llm_usage.dart';

abstract class LlmClient {
  /// 协议实现入口；业务调用方使用 streamCompletion 或 complete。
  Stream<LlmEvent> generate(LlmRequest request, LlmCallControl control);

  Stream<LlmEvent> streamCompletion(
    LlmRequest request, {
    LlmCallControl? control,
  }) {
    final call = control ?? LlmCallControl();
    StreamSubscription<LlmEvent>? subscription;
    LlmUsage? usage;
    late StreamController<LlmEvent> output;
    Object contextualize(Object error, StackTrace stack) {
      if (error is StateError) return error;
      if (error is! LlmException) {
        error = LlmException('响应结构无效', cause: error, causeStackTrace: stack);
      }
      Uri? uri = error.uri;
      try {
        uri ??= const LlmEndpointResolver().resolveGenerationEndpoint(
          rawUrl: request.target.endpoint,
          protocol: request.target.protocol,
        );
      } on LlmEndpointResolverException {
        /* 无效端点不伪造 URI。 */
      }
      return LlmException(
        error.message,
        kind: error.kind,
        requestId: call.requestId,
        protocol: error.protocol ?? request.target.protocol,
        uri: uri,
        statusCode: error.statusCode,
        apiErrorCode: error.apiErrorCode,
        responseBody: error.responseBody,
        usage: error.usage == null
            ? usage
            : usage?.merge(error.usage!) ?? error.usage,
        cause: error.cause,
        causeStackTrace: error.causeStackTrace,
      );
    }

    output = StreamController<LlmEvent>(
      onListen: () {
        try {
          call.claim();
          subscription = generate(request, call).listen(
            (event) {
              if (event.usage case final update?) {
                usage = usage?.merge(update) ?? update;
              }
              output.add(event);
            },
            onError: (Object error, StackTrace stack) {
              output.addError(contextualize(error, stack), stack);
            },
            onDone: output.close,
          );
        } catch (error, stack) {
          output.addError(contextualize(error, stack), stack);
          unawaited(output.close());
        }
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        call.cancel();
        final current = subscription;
        if (current != null) {
          // 订阅者已取消，生成器退出时的错误只属于清理，不能再成为未处理异常。
          unawaited(current.cancel().catchError((Object _, StackTrace _) {}));
        }
      },
    );
    return output.stream;
  }

  Future<LlmResult> complete(
    LlmRequest request, {
    LlmCallControl? control,
  }) async {
    final content = StringBuffer();
    final reasoning = StringBuffer();
    String? finishReason;
    LlmUsage? usage;
    LlmResult? completed;
    await for (final event in streamCompletion(request, control: control)) {
      if (event is LlmCompleted) {
        completed = event.result;
        continue;
      }
      content.write(event.contentDelta);
      reasoning.write(event.reasoningDelta);
      finishReason = event.finishReason ?? finishReason;
      if (event.usage case final update?) {
        usage = usage?.merge(update) ?? update;
      }
    }
    return completed ??
        LlmResult(
          content: content.toString(),
          reasoningContent: reasoning.toString(),
          finishReason: finishReason,
          usage: usage,
        );
  }
}

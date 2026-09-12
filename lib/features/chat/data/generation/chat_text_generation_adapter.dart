import 'dart:async';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_call_control.dart';
import 'package:oh_my_llm/core/llm/llm_client.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';

import '../../application/ports/chat_generation_client.dart';
import 'anthropic/anthropic_message_transformer.dart';
import 'chat_completions/inline_reasoning_tag_splitter.dart';

/// 聊天文本政策留在此边界，共享调用保留模型原始输出。
class ChatTextGenerationAdapter extends ChatGenerationClient {
  ChatTextGenerationAdapter(this.client);
  final LlmClient client;

  @override
  Stream<ChatGenerationChunk> streamCompletion(ChatGenerationRequest request) {
    final control = LlmCallControl();
    StreamSubscription<ChatGenerationChunk>? subscription;
    late StreamController<ChatGenerationChunk> output;
    output = StreamController<ChatGenerationChunk>(
      onListen: () {
        subscription = _stream(
          request,
          control,
        ).listen(output.add, onError: output.addError, onDone: output.close);
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        control.cancel();
        final active = subscription;
        if (active != null) {
          // 订阅者已取消，生成器退出时的错误只属于清理，不能再成为未处理异常。
          unawaited(active.cancel().catchError((Object _, StackTrace _) {}));
        }
      },
    );
    return output.stream;
  }

  Stream<ChatGenerationChunk> _stream(
    ChatGenerationRequest request,
    LlmCallControl control,
  ) async* {
    final protocol = request.target.protocol;
    var input = [
      for (final m in request.messages)
        LlmTextMessage(
          role: LlmRole.values.byName(m.role.name),
          text: m.content,
        ),
    ];
    if (protocol == LlmApiProtocol.anthropic) {
      final transformed = transformAnthropicMessages(request.messages);
      input = [
        if (transformed.system case final system?)
          LlmTextMessage(role: LlmRole.system, text: system),
        for (final m in transformed.messages)
          LlmTextMessage(role: LlmRole.values.byName(m.role), text: m.content),
      ];
    }
    final llmRequest = LlmRequest(
      target: LlmRequestTarget(
        protocol: protocol,
        endpoint: request.target.endpoint,
        apiKey: request.target.apiKey,
        model: request.target.model,
      ),
      input: input,
      options: LlmGenerationOptions(
        reasoningEffort: request.reasoningEffort,
        streamIdleTimeout: request.streamIdleTimeout,
        responseHeaderTimeout: const Duration(seconds: 60),
        maxOutputTokens: protocol == LlmApiProtocol.anthropic ? 8192 : null,
        protocolOptions: switch (protocol) {
          LlmApiProtocol.chatCompletions => null,
          LlmApiProtocol.responses when request.reasoningEffort != null =>
            const ResponsesOptions(
              reasoningSummary: ResponsesReasoningSummary.auto,
              reasoningContext: ResponsesReasoningContext.currentTurn,
            ),
          LlmApiProtocol.responses => null,
          LlmApiProtocol.anthropic => const MessagesOptions(
            automaticCacheControl: true,
          ),
        },
      ),
    );
    final splitter = InlineReasoningTagSplitter();
    var hadContent = false;
    String? diagnosticBody;
    try {
      await for (final event in client.streamCompletion(
        llmRequest,
        control: control,
      )) {
        if (event is LlmCompleted) {
          diagnosticBody = event.result.diagnosticBody;
          continue;
        }
        final split = protocol == LlmApiProtocol.chatCompletions
            ? splitter.splitContent(event.contentDelta)
            : InlineReasoningSplitResult(content: event.contentDelta);
        final chunk = ChatGenerationChunk(
          contentDelta: split.content,
          reasoningDelta: event.reasoningDelta + split.reasoning,
          finishReason: event.finishReason,
          usage: event.usage,
        );
        hadContent |= !chunk.isEmpty;
        yield chunk;
      }
      if (protocol == LlmApiProtocol.chatCompletions) {
        final trailing = splitter.flushRemainder();
        if (trailing != null && !trailing.isEmpty) {
          hadContent = true;
          yield trailing;
        }
      }
      if (!hadContent) {
        throw ChatGenerationException(
          '请求未返回有效内容',
          protocol: protocol,
          responseBody: diagnosticBody,
        );
      }
    } on LlmException catch (error) {
      throw ChatGenerationException(
        error.message,
        protocol: error.protocol,
        uri: error.uri,
        statusCode: error.statusCode,
        apiErrorCode: error.apiErrorCode,
        responseBody: error.responseBody,
        usage: error.usage,
        cause: error.cause,
        causeStackTrace: error.causeStackTrace,
      );
    }
  }
}

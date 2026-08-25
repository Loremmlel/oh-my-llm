import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';

import '../../application/ports/chat_generation_client.dart';
import 'anthropic/anthropic_messages_client.dart';
import 'chat_completions/chat_completions_client.dart';
import 'responses/responses_client.dart';

/// 按请求目标协议委派的生产聊天生成客户端。
///
/// 应用组合层把本客户端作为 chat feature 的唯一客户端绑定；它只根据
/// [ChatGenerationRequest.target.protocol] 把请求转交给对应协议客户端，
/// 不解析 JSON、不转换消息、不修改异常——委派流的 chunk、错误与取消语义
/// 原样透传。`complete()` 由基类折叠 `streamCompletion()` 得到，不覆写。
class ProtocolRoutingChatGenerationClient extends ChatGenerationClient {
  ProtocolRoutingChatGenerationClient({
    required ChatCompletionsClient this._chatCompletions,
    required ResponsesClient this._responses,
    required AnthropicMessagesClient this._anthropic,
  });

  final ChatGenerationClient _chatCompletions;
  final ChatGenerationClient _responses;
  final ChatGenerationClient _anthropic;

  @override
  Stream<ChatGenerationChunk> streamCompletion(ChatGenerationRequest request) {
    // 穷举全部协议，不提供 default 兜底：新增协议时编译器强制补分支，
    // 不会把未知协议静默路由到错误客户端。
    return switch (request.target.protocol) {
      LlmApiProtocol.chatCompletions => _chatCompletions.streamCompletion(
        request,
      ),
      LlmApiProtocol.responses => _responses.streamCompletion(request),
      LlmApiProtocol.anthropic => _anthropic.streamCompletion(request),
    };
  }
}

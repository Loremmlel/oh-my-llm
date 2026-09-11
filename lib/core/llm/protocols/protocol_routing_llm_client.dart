import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_call_control.dart';
import 'package:oh_my_llm/core/llm/llm_client.dart';
import 'package:oh_my_llm/core/llm/llm_event.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';

import 'anthropic/anthropic_messages_client.dart';
import 'chat_completions/chat_completions_client.dart';
import 'responses/responses_client.dart';

/// 按请求目标协议委派的共享单次调用客户端。
///
/// 应用组合层统一装配本客户端，Chat 经自己的文本适配器消费；这里只根据
/// [LlmRequest.target.protocol] 把请求转交给对应协议客户端，
/// 不解析 JSON、不转换消息、不修改异常——委派流的 chunk、错误与取消语义
/// 原样透传。`complete()` 由基类折叠 `streamCompletion()` 得到，不覆写。
class ProtocolRoutingLlmClient extends LlmClient {
  ProtocolRoutingLlmClient({
    required ChatCompletionsClient this._chatCompletions,
    required ResponsesClient this._responses,
    required AnthropicMessagesClient this._anthropic,
  });

  final LlmClient _chatCompletions;
  final LlmClient _responses;
  final LlmClient _anthropic;

  @override
  Stream<LlmEvent> generate(LlmRequest request, LlmCallControl control) {
    // 穷举全部协议，不提供 default 兜底：新增协议时编译器强制补分支，
    // 不会把未知协议静默路由到错误客户端。
    return switch (request.target.protocol) {
      LlmApiProtocol.chatCompletions => _chatCompletions.generate(
        request,
        control,
      ),
      LlmApiProtocol.responses => _responses.generate(request, control),
      LlmApiProtocol.anthropic => _anthropic.generate(request, control),
    };
  }
}

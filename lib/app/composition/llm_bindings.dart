import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/http/custom_headers_provider.dart';
import 'package:oh_my_llm/core/http/http_client_provider.dart';
import 'package:oh_my_llm/core/http/llm_http_stream_transport.dart';
import 'package:oh_my_llm/core/llm/llm_client.dart';
import 'package:oh_my_llm/core/llm/protocols/anthropic/anthropic_messages_client.dart';
import 'package:oh_my_llm/core/llm/protocols/chat_completions/chat_completions_client.dart';
import 'package:oh_my_llm/core/llm/protocols/protocol_routing_llm_client.dart';
import 'package:oh_my_llm/core/llm/protocols/responses/responses_client.dart';
import 'package:oh_my_llm/core/logging/app_network_logger_provider.dart';

/// 仅组合层拥有协议实现，feature 接受各自 port 的绑定。
final llmClientProvider = Provider<LlmClient>((ref) {
  final transport = LlmHttpStreamTransport(
    httpClient: ref.watch(httpClientProvider),
    logger: ref.watch(appNetworkLoggerProvider),
    extraHeadersFactory: () => ref.read(customHeadersMapProvider),
  );
  return ProtocolRoutingLlmClient(
    chatCompletions: ChatCompletionsClient(transport: transport),
    responses: ResponsesClient(transport: transport),
    anthropic: AnthropicMessagesClient(transport: transport),
  );
});

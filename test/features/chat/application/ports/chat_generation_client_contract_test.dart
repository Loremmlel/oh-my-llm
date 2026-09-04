import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_generation_usage.dart';

void main() {
  test('complete 折叠正文、推理、末个 finish reason 与分散 usage', () async {
    final client = _ChunkSequenceClient([
      const ChatGenerationChunk(
        contentDelta: '正',
        usage: ChatGenerationUsage(
          inputTokens: 10,
          cachedInputTokens: 3,
          cacheWriteInputTokens: 2,
        ),
      ),
      const ChatGenerationChunk(
        reasoningDelta: '思考',
        finishReason: 'length',
        usage: ChatGenerationUsage(
          outputTokens: 20,
          reasoningTokens: 5,
          cachedInputTokens: 0,
        ),
      ),
      const ChatGenerationChunk(contentDelta: '文', finishReason: 'stop'),
    ]);

    final result = await client.complete(
      const ChatGenerationRequest(
        target: ChatGenerationRequestTarget(
          protocol: LlmApiProtocol.chatCompletions,
          endpoint: 'https://api.example.com',
          apiKey: 'key',
          model: 'model',
        ),
        messages: [],
      ),
    );

    expect(result.content, '正文');
    expect(result.reasoningContent, '思考');
    expect(result.finishReason, 'stop');
    expect(
      result.usage,
      const ChatGenerationUsage(
        inputTokens: 10,
        outputTokens: 20,
        reasoningTokens: 5,
        cachedInputTokens: 0,
        cacheWriteInputTokens: 2,
      ),
    );
  });
}

final class _ChunkSequenceClient extends ChatGenerationClient {
  _ChunkSequenceClient(this.chunks);

  final List<ChatGenerationChunk> chunks;

  @override
  Stream<ChatGenerationChunk> streamCompletion(ChatGenerationRequest request) {
    return Stream.fromIterable(chunks);
  }
}

import 'dart:async';

import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';

/// 流式补全客户端的测试替身。
///
/// 仅覆写 [streamCompletion]，[complete] 继承基类实现。配合 [enqueueChunks] /
/// [enqueueDeltas] / [enqueueError] 排队响应，[requestHistory] / [requestedModels]
/// 记录调用。供 application / presentation / integration 测试共享。
class FakeChatCompletionClient extends ChatCompletionClient {
  final List<List<ChatCompletionRequestMessage>> requestHistory = [];
  final List<LlmModelConfig> requestedModels = [];
  final List<Stream<ChatCompletionChunk>> _queuedStreams = [];
  List<ChatCompletionRequestMessage> lastRequestMessages = const [];
  LlmModelConfig? lastModelConfig;

  @override
  Stream<ChatCompletionChunk> streamCompletion({
    required LlmModelConfig modelConfig,
    required List<ChatCompletionRequestMessage> messages,
    ReasoningEffort? reasoningEffort,
    Duration? streamIdleTimeout,
  }) {
    lastModelConfig = modelConfig;
    lastRequestMessages = List.unmodifiable(messages);
    requestHistory.add(lastRequestMessages);
    requestedModels.add(modelConfig);
    if (_queuedStreams.isEmpty) {
      return const Stream<ChatCompletionChunk>.empty();
    }

    return _queuedStreams.removeAt(0);
  }

  void enqueueError(Object error) {
    _queuedStreams.add(Stream<ChatCompletionChunk>.error(error));
  }

  void enqueueStream(Stream<ChatCompletionChunk> stream) {
    _queuedStreams.add(stream);
  }

  void enqueueChunks(
    List<String> chunks, {
    Duration chunkDelay = Duration.zero,
  }) {
    _queuedStreams.add(
      _streamDeltas(
        chunks
            .map((chunk) => ChatCompletionChunk(contentDelta: chunk))
            .toList(growable: false),
        chunkDelay,
      ),
    );
  }

  void enqueueDeltas(
    List<ChatCompletionChunk> chunks, {
    Duration chunkDelay = Duration.zero,
  }) {
    _queuedStreams.add(_streamDeltas(chunks, chunkDelay));
  }

  Stream<ChatCompletionChunk> _streamDeltas(
    List<ChatCompletionChunk> chunks,
    Duration chunkDelay,
  ) async* {
    for (final chunk in chunks) {
      if (chunkDelay > Duration.zero) {
        await Future<void>.delayed(chunkDelay);
      }
      yield chunk;
    }
  }
}

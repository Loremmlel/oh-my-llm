import 'dart:async';

import 'package:oh_my_llm/features/chat/application/ports/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';

/// 由测试手动驱动的受控流。
///
/// 持有单订阅 [StreamController]；[listened] 在流的 `onListen` 时完成，
/// 测试先启动 send/run，再 await [listened] 确认开始监听，之后才 [add]
/// chunk——不依赖任何真实延时。
class ControlledChatCompletionStream {
  final StreamController<ChatCompletionChunk> _controller =
      StreamController<ChatCompletionChunk>();
  final Completer<void> _listened = Completer<void>();

  ControlledChatCompletionStream() {
    _controller.onListen = _listened.complete;
  }

  Stream<ChatCompletionChunk> get stream => _controller.stream;

  /// 等待流被 [streamCompletion] 开始监听。
  Future<void> get listened => _listened.future;

  void add(ChatCompletionChunk chunk) => _controller.add(chunk);

  void addError(Object error, [StackTrace? stackTrace]) =>
      _controller.addError(error, stackTrace);

  Future<void> close() => _controller.close();
}

/// 流式补全客户端的测试替身。
///
/// 仅覆写 [streamCompletion]，[complete] 继承基类实现。配合 [enqueueChunks] /
/// [enqueueDeltas] / [enqueueControlledStream] / [enqueueError] 排队响应，
/// [requestHistory] / [requestedModels] 记录调用。供 application /
/// presentation / integration 测试共享。
class FakeChatCompletionClient extends ChatCompletionClient {
  final List<List<ChatCompletionRequestMessage>> requestHistory = [];
  final List<LlmModelConfig> requestedModels = [];

  /// 每次 streamCompletion 调用传入的 streamIdleTimeout，供测试断言超时配置
  /// 是否受会话级自动重试总开关约束。
  final List<Duration?> requestedStreamIdleTimeouts = [];

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
    requestedStreamIdleTimeouts.add(streamIdleTimeout);
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

  /// 排队一条受控流并返回驱动句柄。
  ///
  /// 测试先启动 send/run，再 `await controlled.listened`，之后才发送 chunk。
  ControlledChatCompletionStream enqueueControlledStream() {
    final controlled = ControlledChatCompletionStream();
    _queuedStreams.add(controlled.stream);
    return controlled;
  }

  void enqueueChunks(List<String> chunks) {
    _queuedStreams.add(
      Stream<ChatCompletionChunk>.fromIterable(
        chunks.map((chunk) => ChatCompletionChunk(contentDelta: chunk)),
      ),
    );
  }

  void enqueueDeltas(List<ChatCompletionChunk> chunks) {
    _queuedStreams.add(Stream<ChatCompletionChunk>.fromIterable(chunks));
  }
}

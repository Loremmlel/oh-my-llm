import 'dart:async';

import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';

/// 由测试手动驱动的受控流。
///
/// 持有单订阅 [StreamController]；[listened] 在流的 `onListen` 时完成，
/// 测试先启动 send/run，再 await [listened] 确认开始监听，之后才 [add]
/// chunk——不依赖任何真实延时。
class ControlledChatGenerationStream {
  final StreamController<ChatGenerationChunk> _controller =
      StreamController<ChatGenerationChunk>();
  final Completer<void> _listened = Completer<void>();

  ControlledChatGenerationStream() {
    _controller.onListen = _listened.complete;
  }

  Stream<ChatGenerationChunk> get stream => _controller.stream;

  /// 等待流被 [streamCompletion] 开始监听。
  Future<void> get listened => _listened.future;

  void add(ChatGenerationChunk chunk) => _controller.add(chunk);

  void addError(Object error, [StackTrace? stackTrace]) =>
      _controller.addError(error, stackTrace);

  Future<void> close() => _controller.close();
}

/// 流式生成客户端的测试替身。
///
/// 仅覆写 [streamCompletion]，[complete] 继承基类实现。配合 [enqueueChunks] /
/// [enqueueDeltas] / [enqueueControlledStream] / [enqueueError] 排队响应，
/// [requestHistory] / [requestedTargets] / [lastRequest] 记录调用。供 application /
/// presentation / integration 测试共享。
class FakeChatGenerationClient extends ChatGenerationClient {
  /// 每次调用收到的消息序列（保持旧约定，既有断言直接复用）。
  final List<List<ChatRequestMessage>> requestHistory = [];

  /// 每次调用收到的请求目标，供测试断言请求路由到的协议/端点/模型。
  final List<ChatGenerationRequestTarget> requestedTargets = [];

  /// 每次 streamCompletion 调用传入的 streamIdleTimeout，供测试断言超时配置
  /// 是否受会话级自动重试总开关约束。
  final List<Duration?> requestedStreamIdleTimeouts = [];

  final List<Stream<ChatGenerationChunk>> _queuedStreams = [];
  List<ChatRequestMessage> lastRequestMessages = const [];

  /// 最近一次调用收到的完整请求。
  ChatGenerationRequest? lastRequest;

  @override
  Stream<ChatGenerationChunk> streamCompletion(ChatGenerationRequest request) {
    lastRequest = request;
    lastRequestMessages = List.unmodifiable(request.messages);
    requestHistory.add(lastRequestMessages);
    requestedTargets.add(request.target);
    requestedStreamIdleTimeouts.add(request.streamIdleTimeout);
    if (_queuedStreams.isEmpty) {
      return const Stream<ChatGenerationChunk>.empty();
    }

    return _queuedStreams.removeAt(0);
  }

  void enqueueError(Object error) {
    _queuedStreams.add(Stream<ChatGenerationChunk>.error(error));
  }

  void enqueueStream(Stream<ChatGenerationChunk> stream) {
    _queuedStreams.add(stream);
  }

  /// 排队一条受控流并返回驱动句柄。
  ///
  /// 测试先启动 send/run，再 `await controlled.listened`，之后才发送 chunk。
  ControlledChatGenerationStream enqueueControlledStream() {
    final controlled = ControlledChatGenerationStream();
    _queuedStreams.add(controlled.stream);
    return controlled;
  }

  void enqueueChunks(List<String> chunks) {
    _queuedStreams.add(
      Stream<ChatGenerationChunk>.fromIterable(
        chunks.map((chunk) => ChatGenerationChunk(contentDelta: chunk)),
      ),
    );
  }

  void enqueueDeltas(List<ChatGenerationChunk> chunks) {
    _queuedStreams.add(Stream<ChatGenerationChunk>.fromIterable(chunks));
  }
}

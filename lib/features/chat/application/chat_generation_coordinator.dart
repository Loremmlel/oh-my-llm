import 'dart:async';

import '../data/chat_completion_client.dart';
import 'chat_generation_lifecycle.dart';

/// generation 事件的消费方。
///
/// controller 实现此接口，在 [onGenerationEvent] 中把 typed event 投影到
/// [ChatSessionsState]：chunk 更新 streamingReply，terminal event 触发
/// 消息树落盘与 inline error/empty marker。coordinator 不直接操作 state。
abstract interface class ChatGenerationObserver {
  void onGenerationEvent(ChatGenerationEvent event);
}

/// 单次 generation 的异步时序编排器。
///
/// 只拥有一次 generation 的 attempt、stream subscription、retry window
/// （retry 在 Task 4 接入）与 cancellation token。不读取 Riverpod `ref`、
/// 不操作消息树、不决定 checkpoint 或 prompt 顺序--这些仍由 controller 负责。
///
/// 终态结果经 [ChatGenerationObserver] 投递，controller 据此投影 state。
/// coordinator 不返回永远等待的 Future：[start] 是同步入口，所有异步结果
/// 通过事件回传。
class ChatGenerationCoordinator {
  ChatGenerationCoordinator({required ChatCompletionClient client})
    : _client = client;

  final ChatCompletionClient _client;

  _GenerationHandle? _activeHandle;
  bool _disposed = false;
  int _nextGenerationId = 1;

  /// 启动一次 generation。
  ///
  /// 若已有 generation 在进行，旧 generation 被 supersede（收到 cancelled
  /// 事件后其迟到回调一律被 token guard 丢弃）。新 generation 立即开始。
  void start(ChatGenerationRequest request, ChatGenerationObserver observer) {
    if (_disposed) return;

    final previous = _activeHandle;
    _activeHandle = null;

    final handle = _GenerationHandle(
      generationId: _nextGenerationId++,
      request: request,
      observer: observer,
      dispatch: (event) {
        // dispose 后不再向 observer 投递，避免写入已销毁的 state。
        // 闭包捕获各自 handle 的 observer，避免 supersede 后投递到新 handle。
        if (_disposed) return;
        observer.onGenerationEvent(event);
      },
    );
    _activeHandle = handle;

    // 旧 generation 被取代：先 invalidate 其 token，使其迟到回调被 guard 掉。
    if (previous != null) {
      previous.cancel(ChatCancelReason.superseded);
    }

    _runAttempt(handle);
  }

  /// 用户停止：使 token 失效并尽快取消订阅。
  ///
  /// 幂等：重复调用只产生一次终态。subscription.cancel() 即发即忘，不阻塞
  /// （与现有 stopStreaming 一致：token 空闲间隙时 cancel() 可能迟迟不完成）。
  void stop() {
    final handle = _activeHandle;
    if (handle == null || !handle.isActive) return;
    handle.cancel(ChatCancelReason.userStop);
  }

  /// controller dispose 时调用：取消等待器与订阅，之后任何迟到事件均被忽略。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _activeHandle?.cancel(ChatCancelReason.disposed);
    _activeHandle = null;
  }

  // ── 单 attempt 编排 ────────────────────────────────────────────────────

  void _runAttempt(_GenerationHandle handle) {
    handle.phase = ChatGenerationPhase.preparing;
    handle.notify(
      ChatGenerationStarted(
        generationId: handle.generationId,
        attempt: 1,
        assistantMessageId: handle.request.assistantMessageId,
      ),
    );

    handle.phase = ChatGenerationPhase.streaming;
    try {
      final subscription = _client
          .streamCompletion(
            modelConfig: handle.request.modelConfig,
            messages: handle.request.messages,
            reasoningEffort: handle.request.reasoningEffort,
            streamIdleTimeout: handle.request.streamIdleTimeout,
          )
          .listen(
            (chunk) {
              if (!handle.isActive) return;
              handle.content += chunk.contentDelta;
              handle.reasoning += chunk.reasoningDelta;
              if (chunk.finishReason != null) {
                handle.finishReason = chunk.finishReason;
              }
              handle.notify(
                ChatGenerationChunk(
                  generationId: handle.generationId,
                  contentDelta: chunk.contentDelta,
                  reasoningDelta: chunk.reasoningDelta,
                  finishReason: chunk.finishReason,
                ),
              );
            },
            onDone: () {
              if (!handle.isActive) return;
              _completeAttempt(handle);
            },
            onError: (Object error, StackTrace stack) {
              if (!handle.isActive) return;
              _failAttempt(handle, error, stack);
            },
            cancelOnError: false,
          );
      handle.subscription = subscription;
    } catch (error, stack) {
      if (handle.isActive) {
        _failAttempt(handle, error, stack);
      }
    }
  }

  /// 流正常结束：按累积内容判断成功或空回复。
  ///
  /// output regex 清空正文、异常 finish reason 重试等决策不在 coordinator
  /// 单 attempt 内处理（output processing 留 controller，retry 留 Task 4）。
  void _completeAttempt(_GenerationHandle handle) {
    final isEmpty =
        handle.content.trim().isEmpty && handle.reasoning.trim().isEmpty;
    final ChatGenerationOutcome outcome = isEmpty
        ? ChatGenerationEmptyReply(
            generationId: handle.generationId,
            attempt: 1,
            finishReason: handle.finishReason,
          )
        : ChatGenerationSuccess(
            generationId: handle.generationId,
            attempt: 1,
            content: handle.content,
            reasoningContent: handle.reasoning,
            finishReason: handle.finishReason,
          );
    handle.complete(
      isEmpty ? ChatGenerationPhase.emptyReply : ChatGenerationPhase.succeeded,
      outcome,
    );
    handle.notify(
      ChatGenerationAttemptCompleted(
        generationId: handle.generationId,
        attempt: 1,
        outcome: outcome,
      ),
    );
  }

  void _failAttempt(_GenerationHandle handle, Object error, StackTrace stack) {
    final outcome = ChatGenerationFailure(
      generationId: handle.generationId,
      attempt: 1,
      error: error,
      stackTrace: stack,
    );
    handle.complete(ChatGenerationPhase.failed, outcome);
    handle.notify(
      ChatGenerationAttemptFailed(
        generationId: handle.generationId,
        attempt: 1,
        outcome: outcome,
      ),
    );
  }
}

/// 一次 generation attempt 的内部句柄。
///
/// 持有 token（generationId）、累积缓冲与终态结果。所有迟到回调通过
/// [isActive] 判断是否仍有效：被 cancel 或已进入终态后一律丢弃。
class _GenerationHandle {
  _GenerationHandle({
    required this.generationId,
    required this.request,
    required this.observer,
    required this.dispatch,
  });

  final int generationId;
  final ChatGenerationRequest request;
  final ChatGenerationObserver observer;
  final void Function(ChatGenerationEvent) dispatch;

  StreamSubscription<ChatCompletionChunk>? subscription;
  ChatGenerationPhase phase = ChatGenerationPhase.idle;
  ChatGenerationOutcome? outcome;
  bool _cancelled = false;

  // 累积缓冲：cancel 时取 content 作 partialContent。
  String content = '';
  String reasoning = '';
  String? finishReason;

  /// 仍可处理回调：未取消且未进入终态。
  bool get isActive => !_cancelled && outcome == null;

  /// 取消本次 attempt。
  ///
  /// [ChatCancelReason.userStop] 先经 stopping（投递 stopped 事件携带已收到
  /// 部分内容）再进入 cancelled；supersede/disposed 直接 cancelled。
  /// 幂等：重复调用直接返回。subscription.cancel() 即发即忘。
  void cancel(ChatCancelReason reason) {
    if (_cancelled) return;
    _cancelled = true;
    subscription?.cancel();

    if (outcome != null) return; // 已进入终态，不覆盖。

    if (reason == ChatCancelReason.userStop) {
      phase = ChatGenerationPhase.stopping;
      notify(
        ChatGenerationStopped(
          generationId: generationId,
          partialContent: content,
        ),
      );
    }

    phase = ChatGenerationPhase.cancelled;
    outcome = ChatGenerationCancelled(
      generationId: generationId,
      attempt: 1,
      reason: reason,
      partialContent: content,
    );
    notify(
      ChatGenerationCancelledEvent(generationId: generationId, reason: reason),
    );
  }

  /// 进入终态并记录 outcome。已被 cancel 的 attempt 不接受终态覆盖。
  void complete(
    ChatGenerationPhase terminalPhase,
    ChatGenerationOutcome result,
  ) {
    if (_cancelled) return;
    outcome = result;
    phase = terminalPhase;
  }

  void notify(ChatGenerationEvent event) => dispatch(event);
}

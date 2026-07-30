import 'dart:async';
import 'dart:math';

import '../../settings/domain/models/auto_retry_settings.dart';
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
  void start(
    ChatGenerationRequest request,
    ChatGenerationObserver observer, {
    int? generationId,
  }) {
    if (_disposed) return;

    final previous = _activeHandle;
    _activeHandle = null;

    final handle = _GenerationHandle(
      generationId: generationId ?? _nextGenerationId++,
      request: request,
      observer: observer,
      dispatch: (event) {
        // dispose 后不再向 observer 投递，避免写入已销毁的 state。
        // supersede 后旧 handle 的终态事件（Cancelled）仍需投递，让 observer
        // 得知旧 generation 结束；是否作用于当前状态由 observer 按 generationId
        // 自行判定（见 ChatSessionsController.onGenerationEvent）。旧 attempt 的
        // chunk/complete 由 _GenerationHandle 的 token guard（isActive）拦截，不 dispatch。
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

  /// 当前是否有活跃的 generation。
  bool get hasActive => _activeHandle?.isActive ?? false;

  /// controller 在 attempt 终态后决策重试。返回 false 表示已达上限或不可重试，
  /// controller 应改为终态处理（complete completer + 不再 retry）。
  bool scheduleRetry() {
    final handle = _activeHandle;
    if (handle == null) return false;
    return handle.scheduleRetry(() => _runAttempt(handle));
  }

  /// controller 在 attempt 终态后决策结束 generation。
  void finalize() {
    _activeHandle?.finalize();
  }

  /// controller 在 generation 关键 checkpoint 的 durable save 失败后调用：
  /// 标记 generation 进入 persistenceFailed 终态（取消 retry 等待器与订阅，
  /// 之后迟到回调一律被 token guard 丢弃），不再 retry。幂等。
  ///
  /// 不投递 [ChatGenerationPersistenceFailedEvent]--失败由 controller 自身
  /// 检测并直接投影 state，经 event 往返是冗余；本方法只负责令牌失效与 outcome 记录。
  void markPersistenceFailure(Object error) {
    _activeHandle?.markPersistenceFailure(error);
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
    // 新 attempt：重置终态守卫，确保本次 attempt 能正常产出终态事件。
    handle._attemptSettled = false;
    handle.phase = ChatGenerationPhase.preparing;
    handle.notify(
      ChatGenerationStarted(
        generationId: handle.generationId,
        attempt: handle.attemptCount,
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
    // 拦截 onError 之后的迟到 onDone（cancelOnError:false 下 error 流会先发
    // error 再发 done）：首个终态已投递，第二个直接丢弃。
    if (handle._attemptSettled) return;
    handle._attemptSettled = true;
    final isEmpty =
        handle.content.trim().isEmpty && handle.reasoning.trim().isEmpty;
    final ChatGenerationOutcome attemptOutcome = isEmpty
        ? ChatGenerationEmptyReply(
            generationId: handle.generationId,
            attempt: handle.attemptCount,
            finishReason: handle.finishReason,
          )
        : ChatGenerationSuccess(
            generationId: handle.generationId,
            attempt: handle.attemptCount,
            content: handle.content,
            reasoningContent: handle.reasoning,
            finishReason: handle.finishReason,
          );
    // 不 complete handle：attempt 结束后等 controller 决策 scheduleRetry/finalize。
    handle._attemptOutcome = attemptOutcome;
    handle.phase = isEmpty
        ? ChatGenerationPhase.emptyReply
        : ChatGenerationPhase.succeeded;
    handle.notify(
      ChatGenerationAttemptCompleted(
        generationId: handle.generationId,
        attempt: handle.attemptCount,
        outcome: attemptOutcome,
      ),
    );
  }

  void _failAttempt(_GenerationHandle handle, Object error, StackTrace stack) {
    // 拦截 onDone 之后的迟到 onError（理论上流终止后不再发 error，但与
    // _completeAttempt 的守卫对称，保证一次 attempt 只产出一个终态）。
    if (handle._attemptSettled) return;
    handle._attemptSettled = true;
    final attemptOutcome = ChatGenerationFailure(
      generationId: handle.generationId,
      attempt: handle.attemptCount,
      error: error,
      stackTrace: stack,
    );
    handle._attemptOutcome = attemptOutcome;
    handle.phase = ChatGenerationPhase.failed;
    handle.notify(
      ChatGenerationAttemptFailed(
        generationId: handle.generationId,
        attempt: handle.attemptCount,
        outcome: attemptOutcome,
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
  Timer? _retryTimer;
  int attemptCount = 1;
  ChatGenerationOutcome? _attemptOutcome;
  ChatGenerationPhase phase = ChatGenerationPhase.idle;
  ChatGenerationOutcome? outcome;
  bool _cancelled = false;
  // 本次 attempt 是否已产出终态事件。SSE 流在 cancelOnError:false 下会先发
  // onError 再发 onDone（见 _applySseIdleTimeout 的 fireTimeout：addError 后
  // close）；首个终态后置位，拦截第二个终态回调，避免一次 attempt 同时投递
  // AttemptFailed 与 AttemptCompleted(EmptyReply) 造成状态污染。
  bool _attemptSettled = false;

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
    _retryTimer?.cancel();
    _retryTimer = null;
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

  /// controller 决策终态：标记 generation 结束，不再 retry。
  /// outcome 取当前 attempt 的结果（success/empty/failure），phase 已在
  /// _completeAttempt/_failAttempt 设。已被 cancel 的不覆盖。
  void finalize() {
    if (_cancelled || outcome != null) return;
    outcome = _attemptOutcome;
  }

  /// durable save 失败终态：取消 retry 等待器与订阅，置 persistenceFailed。
  /// 幂等：已被 cancel 或已进入终态的不覆盖。
  void markPersistenceFailure(Object error) {
    if (_cancelled || outcome != null) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    subscription?.cancel();
    phase = ChatGenerationPhase.persistenceFailed;
    outcome = ChatGenerationPersistenceFailure(
      generationId: generationId,
      attempt: attemptCount,
      error: error,
    );
  }

  /// controller 决策重试：等待 retry window 后启动新 attempt。
  /// 返回 false 表示已达 [ChatRetryPolicy.maxRetryCount] 上限或不可重试，
  /// controller 应改为 [finalize]。
  bool scheduleRetry(void Function() onStartNextAttempt) {
    if (_cancelled || outcome != null) return false;
    final policy = request.retryPolicy;
    if (!policy.enabled) return false;
    // maxRetryCount=0 表示不限次（兼容旧行为）；>0 时已跑满 maxRetryCount 次
    // attempt 则不再重试（旧 sendMessageWithAutoRetry 在循环顶部以
    // autoRetryCount > maxRetryCount 判定，等价于 attemptCount >= maxRetryCount）。
    if (policy.maxRetryCount > 0 && attemptCount >= policy.maxRetryCount) {
      return false;
    }
    attemptCount++;
    phase = ChatGenerationPhase.retryWaiting;
    final delay = _computeRetryDelay(policy);
    notify(
      ChatGenerationRetryScheduled(
        generationId: generationId,
        nextAttempt: attemptCount,
        delay: delay,
      ),
    );
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (_cancelled || outcome != null) return;
      // 新 attempt：重置缓冲，保留 generationId / request。
      content = '';
      reasoning = '';
      finishReason = null;
      _attemptOutcome = null;
      onStartNextAttempt();
    });
    return true;
  }

  /// 计算下一次重试的等待时长。
  /// 优先用 [ChatGenerationRequest.retryDelay]（测试注入），否则按 policy 模式：
  /// fixedInterval = 基础间隔 + 0-999ms 抖动；perMinuteWindow = 对齐下一分钟 + 抖动。
  Duration _computeRetryDelay(ChatRetryPolicy policy) {
    final override = request.retryDelay;
    if (override != null) return override;
    if (policy.retryMode == RetryMode.fixedInterval) {
      final jitterMs = Random().nextInt(1000);
      return Duration(milliseconds: policy.maxJitterSeconds * 1000 + jitterMs);
    }
    final now = DateTime.now();
    final msToNextMinute = (60 - now.second) * 1000 - now.millisecond;
    final jitterMs = policy.maxJitterSeconds > 0
        ? Random().nextInt(policy.maxJitterSeconds * 1000)
        : 0;
    return Duration(milliseconds: msToNextMinute + jitterMs);
  }

  void notify(ChatGenerationEvent event) => dispatch(event);
}

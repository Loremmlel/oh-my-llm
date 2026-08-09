import 'dart:async';
import 'dart:math';

import 'package:oh_my_llm/features/settings/domain/models/auto_retry_settings.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_message.dart';
import 'chat_generation_contract.dart';
import 'chat_generation_lifecycle.dart';
import 'chat_sessions_state.dart';
import 'ports/chat_generation_client.dart';

/// 一次 generation 的完整生命周期 owner（不变量 1：单一 owner）。
///
/// 拥有 token（[generationId]）、phase、attempt、停止意图（[_stopIntent]）、
/// terminal outcome、公开完成 Future（[_completion]）与串行执行通道（[_tail]）。
/// 不依赖 Riverpod、不操作消息树、不决定 checkpoint 顺序--这些由
/// [ChatGenerationHost]（controller）负责。run 只驱动状态机并串行化所有
/// awaitable 操作。
///
/// 串行性（不变量 3）：preparing / completeAttempt / stop / retry-fire /
/// terminal-commit 都经 [_serialize] 排队，同一 run 不会有两个 awaitable
/// 操作并发执行。chunk 的 UI 投影 [projectProgress] 保持同步节流，不入队。
class ChatGenerationRun {
  ChatGenerationRun({
    required this.generationId,
    required this.client,
    required this.host,
    required this.command,
    this.streamUiFlushInterval = const Duration(milliseconds: 300),
  });

  final int generationId;
  final ChatGenerationClient client;
  final ChatGenerationHost host;
  final ChatGenerationCommand command;
  final Duration streamUiFlushInterval;

  final Completer<ChatConversation?> _completion =
      Completer<ChatConversation?>();

  /// 串行执行通道：所有 awaitable 操作排队，按入队顺序执行。
  Future<void> _tail = Future<void>.value();

  StreamSubscription<ChatGenerationChunk>? _subscription;
  Timer? _retryTimer;

  ChatGenerationPhase phase = ChatGenerationPhase.idle;
  bool _stopIntent = false;
  bool _disposed = false;
  ChatGenerationOutcome? _outcome; // 非 null 即已 terminal（单一终态 guard）
  int attempt = 1;

  // 累积缓冲。
  String _content = '';
  String _reasoning = '';
  String? _finishReason;
  DateTime _lastFlushAt = DateTime(2000);

  // prepare 填充的 run context。
  ChatGenerationRequest? _request;
  ChatConversation? _streamingConversation;
  ChatMessage? _assistantMessage;
  ChatStreamingReply? _streamingReply;

  /// terminal 完成时 complete。成功带最终会话，取消/失败/persistenceFailed 为 null。
  /// 完成即 durable（不变量 4）：complete 前 host 方法已 await 关键 durable save。
  Future<ChatConversation?> get completion => _completion.future;

  /// run 是否已进入 terminal（completion 已 complete）。coordinator 据此判断 hasActive。
  bool get isTerminal => _completion.isCompleted;

  // ── 公开入口 ────────────────────────────────────────────────────────────────

  /// 启动 generation。返回的 Future 在 prepare 阶段完成后完成（不等 terminal）；
  /// terminal 经 [completion] 观察。
  Future<void> start() => _serialize(_prepare);

  /// 用户停止：幂等（不变量 6）。第一次记录意图 + 入队 stop action；后续 no-op。
  /// 返回的 Future 在 stop action 完成时完成。
  Future<void> requestStop() {
    if (_outcome != null || _stopIntent) return Future<void>.value();
    _stopIntent = true;
    return _serialize(_doStop);
  }

  /// controller dispose 时调用：cancel 订阅/定时器，complete(null)。
  /// 之后任何迟到回调均被 [_disposed] / [_outcome] guard 丢弃。
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _retryTimer?.cancel();
    _retryTimer = null;
    if (!_completion.isCompleted) _completion.complete(null);
  }

  // ── 串行执行通道 ────────────────────────────────────────────────────────────

  /// 把 [action] 排入串行通道。action 内部应处理所有错误路径（转 terminal），
  /// 不向上抛；此处防御性 catch 以防 _tail 破坏导致后续操作永久卡住。
  Future<void> _serialize(Future<void> Function() action) {
    final done = Completer<void>();
    _tail = _tail.then((_) async {
      if (_disposed) {
        done.complete();
        return;
      }
      try {
        await action();
        done.complete();
      } catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }

  // ── prepare ─────────────────────────────────────────────────────────────────

  Future<void> _prepare() async {
    phase = ChatGenerationPhase.preparing;
    _project(); // preparing snapshot（assistantMessageId=null，streamingReply=null）

    final result = await host.prepare(command);
    if (_disposed || _outcome != null) return; // dispose 或已 terminal

    if (result is ChatPrepareFailure) {
      _terminal(
        ChatGenerationPhase.persistenceFailed,
        null,
        outcome: ChatGenerationPersistenceFailure(
          generationId: generationId,
          attempt: attempt,
          error: result.error,
        ),
      );
      return;
    }

    final success = result as ChatPrepareSuccess;
    _request = success.request;
    _streamingConversation = success.streamingConversation;
    _assistantMessage = success.assistantMessage;
    _streamingReply = success.streamingReply;
    _lastFlushAt = DateTime.now().subtract(streamUiFlushInterval);

    // preparing 期间被 stop：不启动网络，stop action 会处理（不变量：preparing
    // stop 不启动网络）。
    if (_stopIntent) return;

    phase = ChatGenerationPhase.streaming;
    _project(streamingReply: _streamingReply);
    _startStream();
  }

  // ── streaming ───────────────────────────────────────────────────────────────

  void _startStream() {
    final request = _request!;
    _subscription = client
        .streamCompletion(request)
        .listen(
          (chunk) {
            // terminal 后丢弃迟到 chunk（token guard）。
            if (_outcome != null) return;
            _content += chunk.contentDelta;
            _reasoning += chunk.reasoningDelta;
            if (chunk.finishReason != null) {
              _finishReason = chunk.finishReason;
            }
            _onChunk();
          },
          onDone: () => _serialize(_completeAttemptFromDone),
          onError: (Object error, StackTrace stack) =>
              _serialize(() => _completeAttemptFromError(error, stack)),
          // error 后自动 cancel：避免 Stream.error 的 error+done 双触发导致同一
          // attempt 被 _completeAttemptFromError 与 _completeAttemptFromDone 各处理
          // 一次（后者 _outcome guard 拦不住 non-terminal Retry，引发额外重试）。
          cancelOnError: true,
        );
  }

  /// chunk 的同步节流投影。不入串行 queue（不变量 3：UI progress 同步）。
  void _onChunk() {
    _streamingReply = _streamingReply?.copyWith(
      content: _content,
      reasoningContent: _reasoning,
      finishReason: _finishReason ?? _streamingReply?.finishReason,
    );
    final now = DateTime.now();
    if (now.difference(_lastFlushAt) < streamUiFlushInterval) return;
    _lastFlushAt = now;
    _project(streamingReply: _streamingReply);
  }

  // ── attempt 终态 ─────────────────────────────────────────────────────────────

  Future<void> _completeAttemptFromDone() async {
    if (_outcome != null) return; // 拦截 onError 后的迟到 onDone
    final isEmpty = _content.trim().isEmpty && _reasoning.trim().isEmpty;
    final ChatGenerationOutcome outcome = isEmpty
        ? ChatGenerationEmptyReply(
            generationId: generationId,
            attempt: attempt,
            finishReason: _finishReason,
          )
        : ChatGenerationSuccess(
            generationId: generationId,
            attempt: attempt,
            content: _content,
            reasoningContent: _reasoning,
            finishReason: _finishReason,
          );
    await _settleAttempt(outcome);
  }

  Future<void> _completeAttemptFromError(Object error, StackTrace stack) async {
    if (_outcome != null) return; // 拦截 onDone 后的迟到 onError
    await _settleAttempt(
      ChatGenerationFailure(
        generationId: generationId,
        attempt: attempt,
        error: error,
        stackTrace: stack,
      ),
    );
  }

  Future<void> _settleAttempt(ChatGenerationOutcome attemptOutcome) async {
    final snapshot = ChatAttemptSnapshot(
      generationId: generationId,
      attempt: attempt,
      attemptOutcome: attemptOutcome,
      streamingConversation: _streamingConversation!,
      assistantMessage: _assistantMessage!,
      streamingReply:
          _streamingReply ??
          ChatStreamingReply(
            conversationId: _streamingConversation!.id,
            assistantMessageId: _assistantMessage!.id,
          ),
      retryPolicy: command.retryPolicy,
    );
    // finalizing：attempt 终态已定，进入 durable save 窗口。保持 busy 阻止新
    // generation 覆盖桥接字段，对外 isStreaming=false（finalizing 不可取消，
    // 不变量 7）。completeAttempt 内的 intermediate/terminal save 均在此窗口内。
    phase = ChatGenerationPhase.finalizing;
    _project();
    final decision = await host.completeAttempt(snapshot);
    if (_disposed || _outcome != null) return;

    switch (decision) {
      case ChatAttemptSucceed(:final conversation):
        _terminal(
          ChatGenerationPhase.succeeded,
          conversation,
          outcome: attemptOutcome,
        );
      case ChatAttemptOutputRuleFailed(:final conversation, :final outcome):
        _terminal(ChatGenerationPhase.failed, conversation, outcome: outcome);
      case ChatAttemptRetry():
        await _scheduleRetry();
      case ChatAttemptGiveUp(:final terminalOutcome):
        _terminal(
          terminalOutcome is ChatGenerationEmptyReply
              ? ChatGenerationPhase.emptyReply
              : ChatGenerationPhase.failed,
          null,
          outcome: terminalOutcome,
        );
      case ChatAttemptPersistenceFailed(:final error):
        _terminal(
          ChatGenerationPhase.persistenceFailed,
          null,
          outcome: ChatGenerationPersistenceFailure(
            generationId: generationId,
            attempt: attempt,
            error: error,
          ),
        );
    }
  }

  // ── retry ────────────────────────────────────────────────────────────────────

  Future<void> _scheduleRetry() async {
    attempt++;
    phase = ChatGenerationPhase.retryWaiting;
    _project(); // retryWaiting，清 streamingReply
    final delay = _computeRetryDelay(command.retryPolicy);
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      _serialize(_startNextAttempt);
    });
  }

  Future<void> _startNextAttempt() async {
    if (_disposed || _outcome != null) return; // retry 等待期间被 stop
    _content = '';
    _reasoning = '';
    _finishReason = null;
    _streamingReply = ChatStreamingReply(
      conversationId: _streamingConversation!.id,
      assistantMessageId: _assistantMessage!.id,
    );
    phase = ChatGenerationPhase.streaming;
    _lastFlushAt = DateTime.now().subtract(streamUiFlushInterval);
    _project(streamingReply: _streamingReply);
    _startStream();
  }

  /// 计算下一次重试等待时长（移植自旧 _GenerationHandle）。
  Duration _computeRetryDelay(ChatRetryPolicy policy) {
    final override = command.retryDelay;
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

  // ── stop ─────────────────────────────────────────────────────────────────────

  Future<void> _doStop() async {
    // finalizing 期间 stop：completeAttempt 已在前序 terminal，no-op
    // （不变量 7：finalizing 不可取消）。
    if (_outcome != null) return;
    // 发起 stop 时的阶段（preparing/streaming/retryWaiting），传入 partial 供
    // host.stop 区分停止来源（ChatPartialSnapshot.phase 契约）。
    final stopOriginPhase = phase;
    // stopping 投影：兼容 bool（isStreaming/isAutoRetryWaiting/autoRetryCount）由
    // 投影统一归位，host.stop 不再单独写（不变量 10）。保留 streamingReply 使已
    // 生成内容在保存窗口仍可见，host.stop 写终态 conversation 后再清。
    phase = ChatGenerationPhase.stopping;
    _project(streamingReply: _streamingReply);
    _subscription?.cancel();
    _retryTimer?.cancel();
    _retryTimer = null;

    final partial = ChatPartialSnapshot(
      generationId: generationId,
      attempt: attempt,
      content: _content,
      reasoning: _reasoning,
      finishReason: _finishReason,
      streamingConversation: _streamingConversation!,
      assistantMessage: _assistantMessage!,
      streamingReply: _streamingReply,
      phase: stopOriginPhase,
    );
    final decision = await host.stop(partial);
    if (_disposed || _outcome != null) return;

    switch (decision) {
      case ChatStopCancelled():
        // cancelled 的 completion 为 null（非成功）；stopStreaming 用
        // state.activeConversation 兜底。stopped conversation 已由 host durable。
        _terminal(
          ChatGenerationPhase.cancelled,
          null,
          outcome: ChatGenerationCancelled(
            generationId: generationId,
            attempt: attempt,
            reason: ChatCancelReason.userStop,
            partialContent: _content,
          ),
        );
      case ChatStopPersistenceFailed(:final error):
        _terminal(
          ChatGenerationPhase.persistenceFailed,
          null,
          outcome: ChatGenerationPersistenceFailure(
            generationId: generationId,
            attempt: attempt,
            error: error,
          ),
        );
    }
  }

  // ── terminal ────────────────────────────────────────────────────────────────

  /// 提交终态（不变量 2：单一终态提交）。幂等：已 terminal 直接返回。
  void _terminal(
    ChatGenerationPhase terminalPhase,
    ChatConversation? conversation, {
    required ChatGenerationOutcome? outcome,
  }) {
    if (_outcome != null) return;
    _outcome = outcome;
    phase = terminalPhase;
    _subscription?.cancel();
    _retryTimer?.cancel();
    _retryTimer = null;
    _project(); // terminal snapshot，清 streamingReply
    if (!_completion.isCompleted) {
      _completion.complete(conversation);
    }
  }

  // ── 投影 ────────────────────────────────────────────────────────────────────

  void _project({ChatStreamingReply? streamingReply}) {
    final outcome = _outcome;
    host.projectProgress(
      ChatGenerationProgress(
        snapshot: ChatGenerationSnapshot(
          generationId: generationId,
          conversationId: _streamingConversation?.id ?? command.conversation.id,
          attempt: attempt,
          phase: phase,
          assistantMessageId: _assistantMessage?.id,
          cancelReason: outcome is ChatGenerationCancelled
              ? outcome.reason
              : null,
          outcome: outcome,
        ),
        streamingReply: streamingReply,
      ),
    );
  }
}

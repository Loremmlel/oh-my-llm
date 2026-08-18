import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/router/app_router.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_notification.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';

/// 流式通知更新节流间隔：同阶段同 attempt 的更新最多每秒一次。
const chatGenerationNotificationUpdateInterval = Duration(seconds: 1);

/// terminal 清理 ACK 失败的有界重试延迟：立即、200ms、800ms 共 3 次尝试。
const chatGenerationNotificationCleanupRetryDelays = <Duration>[
  Duration.zero,
  Duration(milliseconds: 200),
  Duration(milliseconds: 800),
];

/// 定时器工厂：测试注入手动调度器以确定性触发节流与重试定时器。
typedef ChatNotificationTimerFactory =
    Timer Function(Duration duration, void Function() callback);

/// 生产默认定时器工厂（[Timer] 构造函数 tear-off 类型不稳定，显式包装）。
Timer _defaultTimer(Duration duration, void Function() callback) =>
    Timer(duration, callback);

/// 通知投递协调器：把既有 generation 快照串行化投递给前台服务端口。
///
/// 纯编排对象，不持有 Riverpod、不决定生成业务状态，持有的是通知投递瞬态。
/// 职责：
/// - 新 token 首个快照立即请求权限并 start；
/// - 同阶段同 attempt 的 streaming 更新按每秒一次尾缘合并；
/// - phase/attempt/terminal 变化立即投递，不等待节流窗口；
/// - start/update/terminal 经单一 async tail 串行，杜绝先清理后启动；
/// - 旧 token 的迟到定时器/命令/动作/terminal 通过 token 校验丢弃；
/// - 平台失败 fail-open：只影响通知投递，不改写生成结果。
final class ChatGenerationNotificationCoordinator {
  ChatGenerationNotificationCoordinator({
    required ChatGenerationForegroundServicePort port,
    required Future<void> Function() stopGeneration,
    required void Function(String conversationId) openConversation,
    ChatGenerationNotificationProjector projector =
        const ChatGenerationNotificationProjector(),
    DateTime Function()? now,
    ChatNotificationTimerFactory? timerFactory,
    void Function(String category)? logDiagnostic,
  }) : _port = port,
       _stopGeneration = stopGeneration,
       _openConversationCallback = openConversation,
       _projector = projector,
       _now = now ?? DateTime.now,
       _timerFactory = timerFactory ?? _defaultTimer,
       _logDiagnostic = logDiagnostic;

  // ── 注入依赖 ──────────────────────────────────────────────

  final ChatGenerationForegroundServicePort _port;
  final Future<void> Function() _stopGeneration;
  final void Function(String conversationId) _openConversationCallback;
  final ChatGenerationNotificationProjector _projector;
  final DateTime Function() _now;
  final ChatNotificationTimerFactory _timerFactory;
  final void Function(String category)? _logDiagnostic;

  // ── 串行化与生命周期 ──────────────────────────────────────

  /// 命令串行 tail：start/update/terminal 依次执行；单个平台失败不污染后续命令。
  Future<void> _tail = Future<void>.value();
  StreamSubscription<ChatGenerationForegroundAction>? _subscription;
  bool _disposed = false;

  // ── per-token 通知投递瞬态 ────────────────────────────────

  int? _currentToken;
  ChatGenerationPhase? _lastDeliveredPhase;
  int? _lastDeliveredAttempt;
  DateTime? _lastDeliveredAt;
  ChatGenerationCharacterCounts _lastCounts =
      ChatGenerationCharacterCounts.zero;
  Timer? _pendingTimer;
  ChatGenerationNotificationProjection? _pendingProjection;
  bool _tokenUnavailable = false;
  bool _timedOut = false;
  bool _terminalDelivered = false;
  bool _stopInFlight = false;

  /// 订阅原生动作流并取走一次冷启动待打开会话；幂等。
  Future<void> start() async {
    if (_subscription != null) return;
    // 订阅必须先于第一个 await，保证后续 onStateChanged 到来时动作已可达。
    _subscription = _port.actions.listen(
      _handleAction,
      onError: (Object _, StackTrace _) {
        _logDiagnostic?.call('native_action_stream_error');
      },
    );
    // port 实现违反 contract 抛错时兜底：不向 zone 泄漏，订阅保持可用，
    // 冷启动会话取不到只记固定诊断，绝不让 start 半途崩溃。
    final String? pendingConversationId;
    try {
      pendingConversationId = await _port.takePendingOpenConversation();
    } catch (_) {
      _logDiagnostic?.call('take_pending_conversation_failed');
      return;
    }
    if (_disposed || pendingConversationId == null) return;
    _openConversation(pendingConversationId);
  }

  /// 释放动作订阅并取消节流定时器；已入队命令在 [_disposed] 检查处跳过。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelPendingTimer();
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  // ── 状态入口 ──────────────────────────────────────────────

  /// 观察一次 generation 快照并决定是否投递通知命令。
  void onStateChanged({
    required ChatGenerationSnapshot? snapshot,
    required ChatStreamingReply? streamingReply,
  }) {
    if (_disposed || snapshot == null) return; // null 快照不执行任何命令。
    final token = snapshot.generationId;
    final currentToken = _currentToken;
    if (currentToken == null || token > currentToken) {
      if (token <= 0) return; // 防御：非正 token 不是新 generation。
      _resetForNewToken(token);
    } else if (token < currentToken) {
      return; // 旧 token 的迟到快照：不得影响当前 token。
    }

    final ChatGenerationNotificationProjection projection;
    try {
      projection = _projector.project(
        snapshot: snapshot,
        streamingReply: streamingReply,
        fallbackCounts: _lastCounts,
      );
    } on ArgumentError {
      return; // idle 等意外投影：防御性 no-op，不崩溃通知链路。
    }
    if (streamingReply != null) {
      // finalizing 无流式回复时沿用最后一次已知字数。
      _lastCounts = projection.counts;
    }

    if (projection.terminalBehavior !=
        ChatGenerationNotificationTerminalBehavior.ongoing) {
      _deliverTerminal(token, projection);
      return;
    }

    // ongoing 阶段：平台失败或终态已投递后不再投递。
    if (_timedOut || _tokenUnavailable || _terminalDelivered) return;

    final phaseChanged =
        snapshot.phase != _lastDeliveredPhase ||
        snapshot.attempt != _lastDeliveredAttempt;
    if (phaseChanged) {
      // phase/attempt 变化（含新 token 首个快照）：立即投递，不等待节流窗口。
      _cancelPendingTimer();
      _pendingProjection = null;
      final isStart = _lastDeliveredAt == null;
      if (isStart) unawaited(_requestPermission());
      _enqueueDeliver(token, projection, isStart: isStart);
      _markDelivered(snapshot.phase, snapshot.attempt);
      return;
    }

    // 同阶段同 attempt：合并到尾缘，最多每秒一次。
    if (_pendingTimer != null) {
      _pendingProjection = projection; // 同秒内多个 chunk 只保留最后投影。
      return;
    }
    final elapsed = _now().difference(_lastDeliveredAt!);
    if (elapsed >= chatGenerationNotificationUpdateInterval) {
      // 距上次投递已满间隔：立即投递，不重复等待。
      _enqueueDeliver(token, projection, isStart: false);
      _markDelivered(snapshot.phase, snapshot.attempt);
      return;
    }
    _pendingProjection = projection;
    _pendingTimer = _timerFactory(
      chatGenerationNotificationUpdateInterval - elapsed,
      () => _deliverPending(token),
    );
  }

  // ── 命令投递 ──────────────────────────────────────────────

  /// 尾缘定时器触发：投递合并后的最新同阶段投影。
  void _deliverPending(int token) {
    _pendingTimer = null;
    final projection = _pendingProjection;
    _pendingProjection = null;
    if (_disposed || token != _currentToken || projection == null) return;
    if (_timedOut || _tokenUnavailable || _terminalDelivered) return;
    _enqueueDeliver(token, projection, isStart: false);
    // 合并分支保证 phase/attempt 与上次投递相同，只需推进投递时刻。
    _lastDeliveredAt = _now();
  }

  void _enqueueDeliver(
    int token,
    ChatGenerationNotificationProjection projection, {
    required bool isStart,
  }) {
    _enqueue(
      () => _deliverOngoingOp(token, projection.payload, isStart: isStart),
    );
  }

  /// 执行一次 start/update 命令；失败把当前 token 标记为不可用，不再重试。
  ///
  /// 不做 [_terminalDelivered] 检查：在 terminal 之前已入队的 update 属于
  /// 串行契约的一部分，必须按序执行；terminal 之后的 update 已在
  /// [onStateChanged] 源头被抑制，不会入队。
  Future<void> _deliverOngoingOp(
    int token,
    ChatGenerationForegroundPayload payload, {
    required bool isStart,
  }) async {
    if (_disposed || token != _currentToken) return;
    if (_timedOut || _tokenUnavailable) return;
    final result = await _invokeSafely(
      () => isStart ? _port.start(payload) : _port.update(payload),
    );
    if (_disposed || token != _currentToken) return; // 等待期间被取代/销毁。
    if (result.accepted) return;
    _tokenUnavailable = true;
    _logCommandFailure(result.failureCode);
  }

  /// 终态立即投递：remove/fail 清理带固定次数有界重试。
  void _deliverTerminal(
    int token,
    ChatGenerationNotificationProjection projection,
  ) {
    if (_terminalDelivered) return; // 重复 terminal：幂等 no-op。
    _terminalDelivered = true;
    _cancelPendingTimer();
    _pendingProjection = null;
    final behavior = projection.terminalBehavior;
    if (behavior == ChatGenerationNotificationTerminalBehavior.remove) {
      _enqueue(
        () => _terminalCleanupOp(
          token,
          () => _port.remove(
            token: projection.payload.token,
            conversationId: projection.payload.conversationId,
          ),
        ),
      );
    } else {
      _enqueue(
        () => _terminalCleanupOp(token, () => _port.fail(projection.payload)),
      );
    }
  }

  /// terminal 清理：等待 Kotlin ACK，失败按固定延迟有界重试，耗尽后只记诊断。
  Future<void> _terminalCleanupOp(
    int token,
    Future<ChatForegroundCommandResult> Function() command,
  ) async {
    if (_disposed || token != _currentToken) return;
    for (final delay in chatGenerationNotificationCleanupRetryDelays) {
      if (delay > Duration.zero) {
        await _waitFor(delay);
        if (_disposed || token != _currentToken) return; // 等待期间被取代。
      }
      final result = await _invokeSafely(command);
      if (_disposed || token != _currentToken) return;
      if (result.accepted) return;
      _logCommandFailure(result.failureCode);
    }
    _logDiagnostic?.call('cleanup_retry_exhausted');
  }

  /// 经注入定时器工厂等待固定时长（测试可手动触发）。
  Future<void> _waitFor(Duration delay) {
    final completer = Completer<void>();
    _timerFactory(delay, completer.complete);
    return completer.future;
  }

  /// 端口调用兜底：契约外的抛错映射为固定失败分类，不打断串行 tail。
  Future<ChatForegroundCommandResult> _invokeSafely(
    Future<ChatForegroundCommandResult> Function() call,
  ) async {
    try {
      return await call();
    } catch (_) {
      return const ChatForegroundCommandResult.unavailable(
        ChatForegroundFailureCode.nativeFailure,
      );
    }
  }

  /// 串行入队：始终修复 tail，单个平台失败不能毒化后续 terminal 清理。
  void _enqueue(Future<void> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
  }

  /// 与 start 并行触发通知权限查询；结果只影响诊断，不阻断任何命令。
  Future<void> _requestPermission() async {
    final ChatNotificationPermissionStatus status;
    try {
      status = await _port.ensureNotificationPermission();
    } catch (_) {
      if (!_disposed) _logDiagnostic?.call('permission_unavailable');
      return;
    }
    if (_disposed) return;
    if (status == ChatNotificationPermissionStatus.unavailable) {
      _logDiagnostic?.call('permission_unavailable');
    }
  }

  void _markDelivered(ChatGenerationPhase phase, int attempt) {
    _lastDeliveredPhase = phase;
    _lastDeliveredAttempt = attempt;
    _lastDeliveredAt = _now();
  }

  // ── 原生动作 ──────────────────────────────────────────────

  void _handleAction(ChatGenerationForegroundAction action) {
    if (_disposed) return;
    switch (action) {
      case ChatGenerationStopRequested(:final token):
        _handleStopRequested(token);
      case ChatGenerationOpenConversationRequested(:final conversationId):
        _openConversation(conversationId);
      case ChatGenerationForegroundTimedOut(:final token):
        _handleForegroundTimedOut(token);
    }
  }

  /// 停止动作：token 校验 + action-in-flight guard，转发给业务停止路径。
  void _handleStopRequested(int token) {
    if (_currentToken == null || token != _currentToken || _terminalDelivered) {
      _logDiagnostic?.call('stale_native_action');
      return;
    }
    if (_stopInFlight) return; // 重复动作不重复调用 stop。
    _stopInFlight = true;
    // 复用现有 durable stop；协调器不直接关闭 HTTP client。
    // 注入回调可抛错：经 _invokeStopSafely 兜底，失败只记固定诊断，不向 zone 泄漏。
    unawaited(_invokeStopSafely());
  }

  /// 停止注入回调的安全边界：catch 住任何抛错并记录固定诊断分类。
  ///
  /// 与 [_logCommandFailure] 一致：诊断分类固定，不插值 payload/异常文本；
  /// [_stopInFlight] 由下一 token 的 [_resetForNewToken] 清空，不在此回滚。
  Future<void> _invokeStopSafely() async {
    try {
      await _stopGeneration();
    } catch (_) {
      _logDiagnostic?.call('stop_failed');
    }
  }

  /// 平台超时：当前 token 失去前台保护，抑制 ongoing 更新且不重新启动。
  void _handleForegroundTimedOut(int token) {
    if (_currentToken == null || token != _currentToken || _terminalDelivered) {
      _logDiagnostic?.call('stale_native_action');
      return;
    }
    _timedOut = true;
    _cancelPendingTimer();
    _pendingProjection = null;
    _logDiagnostic?.call('platform_timeout');
  }

  void _openConversation(String conversationId) {
    if (_disposed) return;
    _openConversationCallback(conversationId);
  }

  // ── per-token 状态重置 ────────────────────────────────────

  /// 新 generation：重置通知投递瞬态；旧定时器在此取消，旧命令靠
  /// 执行时的 token 校验拒绝，不在此依赖它们已完成。
  void _resetForNewToken(int token) {
    _cancelPendingTimer();
    _pendingProjection = null;
    _currentToken = token;
    _lastDeliveredPhase = null;
    _lastDeliveredAttempt = null;
    _lastDeliveredAt = null;
    _lastCounts = ChatGenerationCharacterCounts.zero;
    _tokenUnavailable = false;
    _timedOut = false;
    _terminalDelivered = false;
    _stopInFlight = false;
  }

  void _cancelPendingTimer() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
  }

  // ── 诊断 ──────────────────────────────────────────────────

  /// 命令失败分类 → 固定脱敏诊断类别；绝不携带 payload/异常/会话 ID。
  void _logCommandFailure(ChatForegroundFailureCode? code) {
    _logDiagnostic?.call(switch (code) {
      ChatForegroundFailureCode.startNotAllowed => 'start_not_allowed',
      ChatForegroundFailureCode.channelTimeout => 'command_timeout',
      _ => 'command_unavailable',
    });
  }
}

/// 应用根部的生成通知协调器 Provider。
///
/// 被 [OhMyLlmApp] eager watch：生命周期不依赖 ChatScreen 是否挂载。读取平台
/// 端口、启动 coordinator（同步订阅动作流后再取走冷启动待打开会话）、观察
/// generation 窄投影，并把 stop/open 动作接到既有业务路径；dispose 时释放。
final chatGenerationNotificationCoordinatorProvider =
    Provider<ChatGenerationNotificationCoordinator>((ref) {
      final coordinator = ChatGenerationNotificationCoordinator(
        port: ref.watch(chatGenerationForegroundServiceProvider),
        // 复用既有 durable stop：phase 停止性由 ChatSessionsController.stopStreaming
        // 强制，coordinator 与绑定均不重复检查阶段。
        stopGeneration: () async {
          await ref.read(chatSessionsProvider.notifier).stopStreaming();
        },
        openConversation: (conversationId) {
          ref
              .read(appRouterProvider)
              .goNamed(
                AppDestination.chat.name,
                queryParameters: {
                  AppRouteParameter.conversationId: conversationId,
                },
              );
        },
        logDiagnostic: (category) {
          debugPrint('[chat-generation-fgs] $category');
        },
      );
      unawaited(coordinator.start());
      ref.listen(
        chatSessionsProvider.select(
          (state) => (state.generation, state.streamingReply),
        ),
        (previous, next) => coordinator.onStateChanged(
          snapshot: next.$1,
          streamingReply: next.$2,
        ),
        fireImmediately: true,
      );
      ref.onDispose(coordinator.dispose);
      return coordinator;
    });

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/notifications/chat_generation_notification_session.dart';
import 'package:oh_my_llm/app/notifications/default_chat_generation_terminal_notifications.dart';
import 'package:oh_my_llm/app/router/app_router.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_notification.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_terminal_notification.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_terminal_notifications.dart';
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

/// 单个 generation token 的通知投递瞬态。
///
/// 新 token 替换 [_currentContext] 时，旧 context 仍会被已入队的 closure 持有
/// 直到 FIFO 完成；因此字段只允许同步入口与「捕获了本 context 的 operation」
/// 读写，operation 执行时绝不允许回读 [_currentContext] 或新 context 字段。
final class _NotificationGenerationContext {
  _NotificationGenerationContext({
    required this.token,
    required this.conversationId,
  });

  final int token;

  /// 当前 generation 所属会话；随每次接受的快照刷新。
  String conversationId;

  ChatGenerationPhase? lastDeliveredPhase;
  int? lastDeliveredAttempt;
  DateTime? lastDeliveredAt;

  /// 最后一次已知的安全字数；只是非成功终态与 timeout 收据的 fallback，
  /// 成功终态的权威计数由收据 projector 从完整 outcome 重算。
  ChatGenerationCharacterCounts lastCounts = ChatGenerationCharacterCounts.zero;

  Timer? pendingTimer;
  ChatGenerationNotificationProjection? pendingProjection;

  /// start/update ACK 失败后为 true：同 token 不再向死通道重试命令。
  bool tokenUnavailable = false;

  /// 平台前台保护已超时：Kotlin 已移除 ongoing，抑制后续 ongoing 投递，
  /// 且真正终态到达时跳过 remove（不再有可清理的通知）。
  bool timedOut = false;

  /// terminal operation 是否已入队：同一 token 的终态只入队一次。
  bool terminalEnqueued = false;

  /// stop 动作 in-flight guard；随新 context 自然重置。
  bool stopInFlight = false;
}

/// 通知协调器：把既有 generation 快照串行化投递给前台服务端口与终态通知端口。
///
/// 纯编排对象，不持有 Riverpod、不决定生成业务状态，持有的是通知投递瞬态。
/// 职责：
/// - 新 token 首个快照立即请求权限并 start；
/// - 同阶段同 attempt 的 streaming 更新按每秒一次尾缘合并；
/// - 真正终态（durable save 后发布的快照）先清理 ongoing 再报告安全收据；
/// - 取消只清理不报告；平台前台保护超时只报告收据且不再触碰前台通道；
/// - start/update/terminal 经单一 async tail 按 FIFO 完成，一旦入队不得被
///   新 generation 取消；
/// - 更小 token 的迟到状态在入口拒绝；ACK 迟到只写回捕获的 context；
/// - 平台失败 fail-open：只影响通知投递，不改写生成结果。
final class ChatGenerationNotificationCoordinator {
  ChatGenerationNotificationCoordinator({
    required ChatGenerationForegroundServicePort port,
    required this.notificationSessionId,
    required ChatGenerationTerminalNotifications terminalNotifications,
    required Future<void> Function() stopGeneration,
    required void Function(String conversationId) openConversation,
    ChatGenerationNotificationProjector projector =
        const ChatGenerationNotificationProjector(),
    DateTime Function()? now,
    ChatNotificationTimerFactory? timerFactory,
    void Function(String category)? logDiagnostic,
  }) : _port = port,
       _terminalNotifications = terminalNotifications,
       _stopGeneration = stopGeneration,
       _openConversationCallback = openConversation,
       _projector = projector,
       _now = now ?? DateTime.now,
       _timerFactory = timerFactory ?? _defaultTimer,
       _logDiagnostic = logDiagnostic;

  // ── 注入依赖 ──────────────────────────────────────────────

  final ChatGenerationForegroundServicePort _port;

  /// 进程级通知 session ID（32 位小写十六进制）；与终态通知深模块共用同一
  /// provider 值，写入 ongoing payload 与终态收据的 event key。
  final String notificationSessionId;

  final ChatGenerationTerminalNotifications _terminalNotifications;
  final Future<void> Function() _stopGeneration;
  final void Function(String conversationId) _openConversationCallback;
  final ChatGenerationNotificationProjector _projector;
  final DateTime Function() _now;
  final ChatNotificationTimerFactory _timerFactory;
  final void Function(String category)? _logDiagnostic;

  // ── 串行化与生命周期 ──────────────────────────────────────

  /// 命令串行 tail：start/update/cleanup/report 依次执行；单个平台失败不污染
  /// 后续 operation。operation 一旦入队必须按 FIFO 完成——旧 token 的迟到
  /// 定时器在入队前被 currency 校验拦截，入队后则不再受 token 取代影响。
  Future<void> _tail = Future<void>.value();
  StreamSubscription<ChatGenerationForegroundAction>? _subscription;
  bool _disposed = false;

  /// 当前 token 的通知瞬态；被更大 token 替换后旧值仅由在途 closure 持有。
  _NotificationGenerationContext? _currentContext;

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
    _cancelPendingTimer(_currentContext);
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  // ── 状态入口 ──────────────────────────────────────────────

  /// 观察一次 generation 快照并决定是否投递通知命令或报告终态收据。
  void onStateChanged({
    required ChatGenerationSnapshot? snapshot,
    required ChatStreamingReply? streamingReply,
  }) {
    if (_disposed || snapshot == null) return; // null 快照不执行任何命令。
    final token = snapshot.generationId;
    final current = _currentContext;
    if (current == null || token > current.token) {
      if (token <= 0) return; // 防御：非正 token 不是新 generation。
      // 替换当前 context：旧 context 上未触发的尾缘定时器随之作废（其回调
      // 本也会被 currency 校验拒绝），但旧 context 已入队的 operation 继续
      // 按 FIFO 完成，不在这里取消。
      _cancelPendingTimer(current);
      current?.pendingProjection = null;
      _currentContext = _NotificationGenerationContext(
        token: token,
        conversationId: snapshot.conversationId,
      );
    } else if (token < current.token) {
      return; // 旧 token 的迟到快照：不得影响当前 token。
    }
    final context = _currentContext!;
    context.conversationId = snapshot.conversationId;

    // 只有 ChatGenerationRun 在 durable save 之后发布的真正终态快照才进入
    // 终态路径；这是收据的唯一来源。
    if (snapshot.phase.isTerminal) {
      _enqueueTerminal(context, snapshot);
      return;
    }

    // 非 terminal 才投影；projector 对 idle 显式抛 ArgumentError，这里防御性
    // no-op，不让意外的空闲投影触碰前台服务。
    final ChatGenerationNotificationProjection projection;
    try {
      projection = _projector.project(
        snapshot: snapshot,
        streamingReply: streamingReply,
        notificationSessionId: notificationSessionId,
        fallbackCounts: context.lastCounts,
      );
    } on ArgumentError {
      return;
    }
    if (streamingReply != null) {
      // finalizing 无流式回复时沿用最后一次已知字数。
      context.lastCounts = projection.counts;
    }

    // 超时/不可用/终态已入队后，抑制尚未入队的 ongoing start/update，
    // 不再重启前台服务。
    if (context.timedOut ||
        context.tokenUnavailable ||
        context.terminalEnqueued) {
      return;
    }

    final phaseChanged =
        snapshot.phase != context.lastDeliveredPhase ||
        snapshot.attempt != context.lastDeliveredAttempt;
    if (phaseChanged) {
      // phase/attempt 变化（含新 token 首个快照）：立即投递，不等待节流窗口。
      _cancelPendingTimer(context);
      context.pendingProjection = null;
      final isStart = context.lastDeliveredAt == null;
      if (isStart) unawaited(_requestPermission());
      _enqueueDeliver(context, projection, isStart: isStart);
      _markDelivered(context, snapshot.phase, snapshot.attempt);
      return;
    }

    // 同阶段同 attempt：合并到尾缘，最多每秒一次。
    if (context.pendingTimer != null) {
      context.pendingProjection = projection; // 同秒内多个 chunk 只保留最后投影。
      return;
    }
    final elapsed = _now().difference(context.lastDeliveredAt!);
    if (elapsed >= chatGenerationNotificationUpdateInterval) {
      // 距上次投递已满间隔：立即投递，不重复等待。
      _enqueueDeliver(context, projection, isStart: false);
      _markDelivered(context, snapshot.phase, snapshot.attempt);
      return;
    }
    context.pendingProjection = projection;
    context.pendingTimer = _timerFactory(
      chatGenerationNotificationUpdateInterval - elapsed,
      () => _deliverPending(context),
    );
  }

  // ── 命令投递 ──────────────────────────────────────────────

  /// 尾缘定时器触发：投递合并后的最新同阶段投影。
  ///
  /// 触发时确认捕获的 context 仍是 current 且未终态，再入队；一旦入队，
  /// operation 必须按 FIFO 执行。
  void _deliverPending(_NotificationGenerationContext context) {
    context.pendingTimer = null;
    final projection = context.pendingProjection;
    context.pendingProjection = null;
    if (_disposed || projection == null) return;
    if (_currentContext != context || context.terminalEnqueued) return;
    if (context.timedOut || context.tokenUnavailable) return;
    _enqueueDeliver(context, projection, isStart: false);
    // 合并分支保证 phase/attempt 与上次投递相同，只需推进投递时刻。
    context.lastDeliveredAt = _now();
  }

  void _enqueueDeliver(
    _NotificationGenerationContext context,
    ChatGenerationNotificationProjection projection, {
    required bool isStart,
  }) {
    _enqueue(
      () => _deliverOngoingOp(context, projection.payload, isStart: isStart),
    );
  }

  /// 执行一次已入队的 start/update 命令。
  ///
  /// 不做 current-token 校验：operation 一旦入队就必须按 FIFO 完成，新 token
  /// 不得取消它。ACK 返回后只修改捕获的 context，绝不把本 token 的失败写到
  /// 新 token。terminal 之前已入队的 update 属于串行契约的一部分，按序执行；
  /// terminal 之后的 update 已在 [onStateChanged] 源头被抑制，不会入队。
  Future<void> _deliverOngoingOp(
    _NotificationGenerationContext context,
    ChatGenerationForegroundPayload payload, {
    required bool isStart,
  }) async {
    if (_disposed) return;
    // 同 token 前序命令已把通道判死时不再重试；这是通道级 fail-open，
    // 与 FIFO 完成语义无关。
    if (context.tokenUnavailable) return;
    // timeout 后 Kotlin 已移除 ongoing 并停止服务：已入队的 update 不再补发，
    // 避免对已停止的服务打 FAILURE_SERVICE_UNAVAILABLE。
    if (context.timedOut) return;
    final result = await _invokeSafely(
      () => isStart ? _port.start(payload) : _port.update(payload),
    );
    if (_disposed) return; // 等待期间销毁。
    if (result.accepted) return;
    // channelTimeout 是 2s 上界的假阴性：原生可能已接受（慢设备 promotion），
    // 不得据此判死通道；其余失败（startNotAllowed/security/...）才置不可用。
    if (result.failureCode != ChatForegroundFailureCode.channelTimeout) {
      context.tokenUnavailable = true;
    }
    _logCommandFailure(result.failureCode);
  }

  /// 终态入口：投影收据并按固定顺序入队 cleanup -> report。
  ///
  /// 同一 context 只允许 terminal 入队一次；总是取消该 context 的 pending
  /// timer。closure 捕获 context/receipt/conversationId，执行时不再比较
  /// [_currentContext]，也不读取新 token 的任何字段；remove 的跳过判定
  /// （timedOut）由 [_terminalOp] 在执行时读取捕获的 context。
  void _enqueueTerminal(
    _NotificationGenerationContext context,
    ChatGenerationSnapshot snapshot,
  ) {
    final receipt = projectChatGenerationTerminalReceipt(
      notificationSessionId: notificationSessionId,
      snapshot: snapshot,
      counts: context.lastCounts,
    );
    _cancelPendingTimer(context);
    context.pendingProjection = null;
    if (context.terminalEnqueued) return; // 重复 terminal：幂等 no-op。
    context.terminalEnqueued = true;
    final conversationId = snapshot.conversationId;
    _enqueue(() => _terminalOp(context, receipt, conversationId));
  }

  /// 终态收口：timedOut=false 时先清理 ongoing，成功或耗尽后都报告收据。
  ///
  /// 串行 cleanup 后 report 是有意的产品权衡：避免 Android 同时展示「仍在
  /// 生成」的 ongoing 与「生成已结束」的终态通知。单次 cleanup 的上界为三次
  /// 2 秒 channel timeout 加 200ms/800ms 退避共 7 秒；若 tail 前面还有在途
  /// native command，还需加上其剩余等待时间。cleanup 失败不得阻止真正终态
  /// 通知（report 自己 fail-open）。
  Future<void> _terminalOp(
    _NotificationGenerationContext context,
    ChatGenerationTerminalReceipt? receipt,
    String conversationId,
  ) async {
    if (_disposed) return;
    // 执行时才判定 skipRemove：若 terminal 入队后、remove 执行前收到了平台
    // 超时（Kotlin 已自行移除 ongoing 并停止服务），这里读到 timedOut=true
    // 就跳过 remove，不再对已停止的服务打 FAILURE_SERVICE_UNAVAILABLE。
    final skipRemove = context.timedOut;
    // cancellation 收据为 null 只 cleanup；timeout 已清理（timedOut=true）时
    // Kotlin 侧已无可清理通知，完全 no-op（receipt 也必为 null）或直接 report。
    if (!skipRemove) {
      await _cleanupOngoing(context.token, conversationId);
      if (_disposed) return;
    }
    if (receipt != null) {
      await _reportSafely(receipt);
    }
  }

  /// ongoing 清理：等待原生 ACK，失败按固定延迟有界重试，耗尽后只记诊断。
  ///
  /// 三次重试只受 dispose 取消，不受新 generation 影响——旧 token 的通知
  /// 残留同样必须清掉。重试上界见 [_terminalOp] 注释。
  Future<void> _cleanupOngoing(int token, String conversationId) async {
    for (final delay in chatGenerationNotificationCleanupRetryDelays) {
      if (delay > Duration.zero) {
        await _waitFor(delay);
        if (_disposed) return; // 重试只被 dispose 打断。
      }
      final result = await _invokeSafely(
        () => _port.remove(token: token, conversationId: conversationId),
      );
      if (_disposed) return;
      if (result.accepted) return;
      _logCommandFailure(result.failureCode);
    }
    _logDiagnostic?.call('cleanup_retry_exhausted');
  }

  /// 终态报告边界：report 契约上 fail-open，契约外抛错兜底为固定诊断，
  /// 不打断串行 tail，也不毒化后续 operation。
  Future<void> _reportSafely(ChatGenerationTerminalReceipt receipt) async {
    try {
      await _terminalNotifications.report(receipt);
    } catch (_) {
      _logDiagnostic?.call('terminal_report_failed');
    }
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

  void _markDelivered(
    _NotificationGenerationContext context,
    ChatGenerationPhase phase,
    int attempt,
  ) {
    context.lastDeliveredPhase = phase;
    context.lastDeliveredAttempt = attempt;
    context.lastDeliveredAt = _now();
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
    final context = _currentContext;
    if (context == null || token != context.token || context.terminalEnqueued) {
      _logDiagnostic?.call('stale_native_action');
      return;
    }
    if (context.stopInFlight) return; // 重复动作不重复调用 stop。
    context.stopInFlight = true;
    // 复用现有 durable stop；协调器不直接关闭 HTTP client。
    // 注入回调可抛错：经 _invokeStopSafely 兜底，失败只记固定诊断，不向 zone 泄漏。
    unawaited(_invokeStopSafely());
  }

  /// 停止注入回调的安全边界：catch 住任何抛错并记录固定诊断分类。
  ///
  /// 与 [_logCommandFailure] 一致：诊断分类固定，不插值 payload/异常文本；
  /// [stopInFlight] 由下一 token 的新 context 自然清空，不在此回滚。
  Future<void> _invokeStopSafely() async {
    try {
      await _stopGeneration();
    } catch (_) {
      _logDiagnostic?.call('stop_failed');
    }
  }

  /// 平台前台保护超时：只置位 timedOut，不再调用 remove、不停止生成。
  ///
  /// Kotlin 在发 callback 前已经移除 ongoing 并停止 Service，Dart 若再经
  /// MethodChannel 调 remove 会形成原生重入；因此这里只置位标记、取消挂起
  /// 更新，并把收据 report 加入同一个 async tail。若终态收据已入队（真正
  /// 终态快照先到），只置位 timedOut 让已入队的 terminal op 执行时跳过
  /// remove，不再重复报告 timeout 收据。
  void _handleForegroundTimedOut(int token) {
    final context = _currentContext;
    if (context == null || token != context.token) {
      _logDiagnostic?.call('stale_native_action');
      return;
    }
    if (context.timedOut) return; // 重复 timeout 幂等：收据只会入队一次。
    context.timedOut = true;
    _cancelPendingTimer(context);
    context.pendingProjection = null;
    if (context.terminalEnqueued) {
      // 终态已入队：只置 timedOut 让已入队的 terminal op 执行时跳过 remove，
      // 不再重复报告 timeout 收据（终态收据已在 FIFO 中）。
      _logDiagnostic?.call('platform_timeout');
      return;
    }
    final receipt = ChatGenerationTerminalReceipt(
      notificationSessionId: notificationSessionId,
      generationId: context.token,
      conversationId: context.conversationId,
      terminalKind: ChatGenerationTerminalKind.foregroundProtectionTimedOut,
      contentCount: context.lastCounts.content,
      reasoningCount: context.lastCounts.reasoning,
      failureKind: ChatGenerationTerminalFailureKind.foregroundProtection,
    );
    _enqueue(() => _reportTimeoutReceipt(receipt));
    _logDiagnostic?.call('platform_timeout');
  }

  Future<void> _reportTimeoutReceipt(
    ChatGenerationTerminalReceipt receipt,
  ) async {
    if (_disposed) return;
    await _reportSafely(receipt);
  }

  void _openConversation(String conversationId) {
    if (_disposed) return;
    // 注入回调（composition 的 goNamed）契约外抛错时兜底：只记固定诊断，
    // 不向动作流的 zone 泄漏，与 _invokeStopSafely 的兜底语义一致。
    try {
      _openConversationCallback(conversationId);
    } catch (_) {
      _logDiagnostic?.call('open_conversation_failed');
    }
  }

  // ── 定时器辅助 ────────────────────────────────────────────

  void _cancelPendingTimer(_NotificationGenerationContext? context) {
    context?.pendingTimer?.cancel();
    if (context != null) {
      context.pendingTimer = null;
    }
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
/// 端口、进程级通知 session（与默认终态通知深模块共用同一 provider 值）和
/// 终态通知端口，启动 coordinator（同步订阅动作流后再取走冷启动待打开会话），
/// 观察 generation 窄投影，并把 stop/open 动作接到既有业务路径；dispose 时释放。
final chatGenerationNotificationCoordinatorProvider =
    Provider<ChatGenerationNotificationCoordinator>((ref) {
      final coordinator = ChatGenerationNotificationCoordinator(
        port: ref.watch(chatGenerationForegroundServiceProvider),
        // session 由 app composition 每个 ProviderScope 只生成一次；coordinator
        // 与终态通知深模块必须读同一个值，不得各自再生成一份。
        notificationSessionId: ref.watch(
          chatGenerationNotificationSessionIdProvider,
        ),
        terminalNotifications: ref.watch(
          chatGenerationTerminalNotificationsProvider,
        ),
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

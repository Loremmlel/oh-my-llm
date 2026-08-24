import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/composition/chat_generation_notification_coordinator.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_terminal_notification.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_terminal_notifications.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_state.dart';

/// 测试固定通知 session（32 位小写十六进制）；生产由 composition 一次性生成。
const _notificationSessionId = '000102030405060708090a0b0c0d0e0f';

/// 构造指定阶段的 generation 快照；终态调用方自行传入匹配的 outcome。
ChatGenerationSnapshot _snapshot(
  ChatGenerationPhase phase, {
  int generationId = 1,
  String conversationId = 'conv-1',
  int attempt = 1,
  ChatGenerationOutcome? outcome,
}) {
  return ChatGenerationSnapshot(
    generationId: generationId,
    conversationId: conversationId,
    attempt: attempt,
    phase: phase,
    outcome: outcome,
  );
}

/// 终态阶段配套的典型 outcome（与 phase 一一对应，遵循 snapshot invariant）。
ChatGenerationOutcome _outcomeFor(
  ChatGenerationPhase phase, {
  int generationId = 1,
  int attempt = 1,
}) {
  return switch (phase) {
    ChatGenerationPhase.succeeded => ChatGenerationSuccess(
      generationId: generationId,
      attempt: attempt,
      content: '好',
      reasoningContent: '',
    ),
    ChatGenerationPhase.cancelled => ChatGenerationCancelled(
      generationId: generationId,
      attempt: attempt,
      reason: ChatCancelReason.userStop,
    ),
    ChatGenerationPhase.emptyReply => ChatGenerationEmptyReply(
      generationId: generationId,
      attempt: attempt,
    ),
    ChatGenerationPhase.failed => ChatGenerationFailure(
      generationId: generationId,
      attempt: attempt,
      error: StateError('网络失败'),
    ),
    ChatGenerationPhase.persistenceFailed => ChatGenerationPersistenceFailure(
      generationId: generationId,
      attempt: attempt,
      error: StateError('写盘失败'),
    ),
    _ => throw ArgumentError('非终态阶段无需 outcome：$phase'),
  };
}

/// 构造一条流式回复（默认属于 conv-1）。
ChatStreamingReply _reply(String content, String reasoning) {
  return ChatStreamingReply(
    conversationId: 'conv-1',
    assistantMessageId: 'assistant-1',
    content: content,
    reasoningContent: reasoning,
  );
}

/// 让串行命令 tail 的微任务排空；端口调用在调用时刻同步记录到 fake。
Future<void> _flushTail() => pumpEventQueue();

/// 手动定时器：不依赖真实时钟，由测试显式触发；cancel 后不再回调。
final class ManualTimer implements Timer {
  ManualTimer(this.duration, this.callback);

  final Duration duration;
  final void Function() callback;
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;

  /// 触发回调；[force] 为 true 时即使已取消也触发，用于模拟
  /// 「回调已在事件队列中就绪后定时器才被取消」的竞态。
  void fire({bool force = false}) {
    if (force || !cancelled) callback();
  }
}

/// 手动定时器调度器：记录经 timerFactory 创建的全部定时器，由测试触发。
final class TestTimerScheduler {
  final _pending = <ManualTimer>[];

  Timer create(Duration duration, void Function() callback) {
    final timer = ManualTimer(duration, callback);
    _pending.add(timer);
    return timer;
  }

  /// 仍活跃（未被取消）的定时器。
  List<ManualTimer> get pending =>
      List.unmodifiable(_pending.where((t) => !t.cancelled));

  /// 触发并移除下一个定时器（已取消的定时器触发为 no-op）。
  void fireNext() {
    final timer = _pending.removeAt(0);
    timer.fire();
  }
}

/// 可手动推进的时钟，配合节流间隔判定与 7 秒上界推演。
final class TestClock {
  DateTime current = DateTime(2026, 1, 1);

  DateTime call() => current;

  void advance(Duration duration) => current = current.add(duration);
}

/// 确定性端口 fake：命令调用同步记录到 [calls]，结果按 [queuedResults] 顺序返回，
/// 队列为空时默认 accepted。[sharedLog] 与终态通知 fake 共享，用于断言
/// 「cleanup 先于 report」「start1 -> cleanup -> report -> start2」这类跨端口顺序。
final class FakeChatGenerationForegroundService
    implements ChatGenerationForegroundServicePort {
  FakeChatGenerationForegroundService({this.sharedLog});

  /// 跨端口共享的时序记录：start/update 记 `名称:token`，remove 记 `remove`。
  final List<String>? sharedLog;

  final actionsController =
      StreamController<ChatGenerationForegroundAction>.broadcast();
  final calls = <String>[];
  final payloads = <ChatGenerationForegroundPayload>[];
  final queuedResults = Queue<Future<ChatForegroundCommandResult>>();

  /// 待打开的冷启动会话 ID；[takePendingOpenConversation] 返回它。
  String? pendingOpenConversationId;

  /// 非 null 时阻塞 [takePendingOpenConversation]，用于验证订阅先于第一个 await。
  Completer<void>? takePendingGate;

  /// 为 true 时 [takePendingOpenConversation] 抛错，验证 start 的兜底路径。
  bool throwOnTakePending = false;

  /// 权限查询结果。
  ChatNotificationPermissionStatus permissionStatus =
      ChatNotificationPermissionStatus.granted;

  @override
  Stream<ChatGenerationForegroundAction> get actions =>
      actionsController.stream;

  Future<ChatForegroundCommandResult> _record(
    String name,
    ChatGenerationForegroundPayload? payload,
  ) {
    calls.add(name);
    if (payload != null) {
      payloads.add(payload);
      sharedLog?.add('$name:${payload.token}');
    } else {
      sharedLog?.add(name);
    }
    return queuedResults.isEmpty
        ? Future.value(const ChatForegroundCommandResult.accepted())
        : queuedResults.removeFirst();
  }

  @override
  Future<ChatNotificationPermissionStatus> ensureNotificationPermission() {
    calls.add('ensureNotificationPermission');
    return Future.value(permissionStatus);
  }

  @override
  Future<ChatForegroundCommandResult> start(
    ChatGenerationForegroundPayload payload,
  ) => _record('start', payload);

  @override
  Future<ChatForegroundCommandResult> update(
    ChatGenerationForegroundPayload payload,
  ) => _record('update', payload);

  @override
  Future<ChatForegroundCommandResult> remove({
    required int token,
    required String conversationId,
  }) => _record('remove', null);

  @override
  Future<String?> takePendingOpenConversation() async {
    calls.add('takePendingOpenConversation');
    if (throwOnTakePending) throw StateError('take pending 失败');
    final gate = takePendingGate;
    if (gate != null) await gate.future;
    return pendingOpenConversationId;
  }

  @override
  void dispose() {
    // 动作流仅在测试 teardown 关闭，避免与协调器订阅取消的先后顺序耦合。
    if (!actionsController.isClosed) actionsController.close();
  }
}

/// 终态通知端口 fake：记录收据与共享时序；可注入契约外抛错验证兜底。
final class FakeChatGenerationTerminalNotifications
    implements ChatGenerationTerminalNotifications {
  FakeChatGenerationTerminalNotifications({this.sharedLog});

  /// 与前台端口 fake 共享的时序记录；report 记 `report:<kind>:<generationId>`。
  final List<String>? sharedLog;

  final receipts = <ChatGenerationTerminalReceipt>[];

  /// 每次 report 收到的 suppressedAtTerminal 参数（断言冻结决策被传递）。
  final reportsWithSuppression = <bool?>[];

  /// 为 true 时 report 抛契约外异常，验证 coordinator 兜底不毒化。
  bool throwOnReport = false;

  @override
  Future<void> report(
    ChatGenerationTerminalReceipt receipt, {
    bool? suppressedAtTerminal,
  }) async {
    reportsWithSuppression.add(suppressedAtTerminal);
    sharedLog?.add(
      'report:${receipt.terminalKind.name}:${receipt.generationId}',
    );
    receipts.add(receipt);
    if (throwOnReport) throw StateError('report 契约外失败');
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late FakeChatGenerationForegroundService port;
  late FakeChatGenerationTerminalNotifications terminalNotifications;
  late TestTimerScheduler timers;
  late TestClock clock;
  late ChatGenerationNotificationCoordinator coordinator;
  final sharedLog = <String>[];
  final diagnostics = <String>[];
  final stopCalls = <String>[];
  final openedConversationIds = <String>[];

  setUp(() {
    port = FakeChatGenerationForegroundService(sharedLog: sharedLog);
    terminalNotifications = FakeChatGenerationTerminalNotifications(
      sharedLog: sharedLog,
    );
    timers = TestTimerScheduler();
    clock = TestClock();
    sharedLog.clear();
    diagnostics.clear();
    stopCalls.clear();
    openedConversationIds.clear();
    coordinator = ChatGenerationNotificationCoordinator(
      port: port,
      notificationSessionId: _notificationSessionId,
      terminalNotifications: terminalNotifications,
      stopGeneration: () async => stopCalls.add('stop'),
      openConversation: openedConversationIds.add,
      now: clock.call,
      timerFactory: timers.create,
      logDiagnostic: diagnostics.add,
    );
  });

  tearDown(() {
    coordinator.dispose();
    port.dispose();
  });

  group('启动与状态入口', () {
    test('preparing 立即排队权限与 start', () async {
      await coordinator.start();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();
      expect(port.calls, [
        'takePendingOpenConversation',
        'ensureNotificationPermission',
        'start',
      ]);
      expect(port.payloads.single.token, 1);
      expect(port.payloads.single.conversationId, 'conv-1');
      expect(
        port.payloads.single.actionKind,
        ChatGenerationNotificationActionKind.stop,
      );
    });

    test('ongoing warm 与 pending 点击仍转发到现有 openConversation 回调', () async {
      // 冷启动 pending：start() 内取走一次并导航。
      port.pendingOpenConversationId = 'conv-pending';
      await coordinator.start();
      expect(openedConversationIds, ['conv-pending']);
      expect(
        port.calls.where((c) => c == 'takePendingOpenConversation').length,
        1,
      );

      // warm 动作流：运行期点击 ongoing 通知直达对应会话。
      port.actionsController.add(
        const ChatGenerationOpenConversationRequested('conv-warm'),
      );
      await _flushTail();
      expect(openedConversationIds, ['conv-pending', 'conv-warm']);

      // 幂等：重复 start 不再取走第二次 pending。
      await coordinator.start();
      expect(
        port.calls.where((c) => c == 'takePendingOpenConversation').length,
        1,
      );
    });

    test('start 先同步订阅动作流，再取走一次待打开会话', () async {
      port.takePendingGate = Completer<void>();
      port.pendingOpenConversationId = 'conv-pending';
      final startFuture = coordinator.start();
      // takePendingOpenConversation 仍阻塞时动作流已可触达：订阅先于第一个 await。
      port.actionsController.add(
        const ChatGenerationOpenConversationRequested('conv-early'),
      );
      await _flushTail();
      expect(openedConversationIds, ['conv-early']);
      port.takePendingGate!.complete();
      await startFuture;
      expect(openedConversationIds, ['conv-early', 'conv-pending']);
      expect(port.calls, ['takePendingOpenConversation']);
    });

    test('takePendingOpenConversation 抛错时 start 兜底记录诊断且订阅仍可用', () async {
      port.throwOnTakePending = true;
      await coordinator.start();
      expect(diagnostics, ['take_pending_conversation_failed']);

      // 订阅未受影响：动作流仍可触达，协调器保持可用，不会因异常永久卡死。
      port.actionsController.add(
        const ChatGenerationOpenConversationRequested('conv-after-fail'),
      );
      await _flushTail();
      expect(openedConversationIds, ['conv-after-fail']);
    });

    test('snapshot 为 null 时不执行任何命令', () async {
      await coordinator.start();
      coordinator.onStateChanged(snapshot: null, streamingReply: null);
      await _flushTail();
      expect(port.calls, ['takePendingOpenConversation']);
    });

    test('意外 idle 快照被防御性忽略，不崩溃通知链路', () async {
      await coordinator.start();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.idle),
        streamingReply: null,
      );
      await _flushTail();
      expect(port.calls, ['takePendingOpenConversation']);
    });

    test('权限查询不可用时记录固定诊断，不影响 start', () async {
      port.permissionStatus = ChatNotificationPermissionStatus.unavailable;
      await coordinator.start();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();
      expect(
        port.calls,
        containsAllInOrder(['ensureNotificationPermission', 'start']),
      );
      expect(diagnostics, ['permission_unavailable']);
    });
  });

  group('节流', () {
    test('同阶段流式更新合并为尾缘投递，最多每秒一次', () async {
      await coordinator.start();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();

      // 阶段变化（preparing → streaming）立即投递。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming),
        streamingReply: _reply('你', ''),
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'update').length, 1);

      // 同阶段同 attempt 的两个 chunk 合并，尾缘只投递最后一个。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming),
        streamingReply: _reply('你好', ''),
      );
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming),
        streamingReply: _reply('你好呀', ''),
      );
      expect(timers.pending, hasLength(1));
      expect(
        timers.pending.single.duration,
        chatGenerationNotificationUpdateInterval,
      );
      timers.fireNext();
      await _flushTail();
      expect(port.calls.where((c) => c == 'update').length, 2);
      expect(port.payloads.last.text, '正文 3 字 · 推理 0 字');

      // 距上次投递满 1 秒后，同阶段更新不再等待尾缘。
      clock.advance(chatGenerationNotificationUpdateInterval);
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming),
        streamingReply: _reply('好', '好'),
      );
      expect(timers.pending, isEmpty);
      await _flushTail();
      expect(port.calls.where((c) => c == 'update').length, 3);
      expect(port.payloads.last.text, '正文 1 字 · 推理 1 字');
    });

    test('阶段或 attempt 变化取消挂起的尾缘定时器并立即投递', () async {
      await coordinator.start();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming),
        streamingReply: _reply('你', ''),
      );
      await _flushTail();
      // 同阶段同 attempt 更新挂起尾缘定时器。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming),
        streamingReply: _reply('你好', ''),
      );
      expect(timers.pending, hasLength(1));

      // attempt 变化：取消定时器并立即投递。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming, attempt: 2),
        streamingReply: _reply('重试', ''),
      );
      expect(timers.pending, isEmpty);
      await _flushTail();
      expect(port.payloads.last.text, '正文 2 字 · 推理 0 字');

      // 阶段变化（streaming → stopping）同样取消定时器并立即投递。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming, attempt: 2),
        streamingReply: _reply('再试', ''),
      );
      expect(timers.pending, hasLength(1));
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.stopping),
        streamingReply: null,
      );
      expect(timers.pending, isEmpty);
      await _flushTail();
      expect(port.payloads.last.title, '正在停止');
    });

    test('finalizing 沿用最后一次已知字数', () async {
      await coordinator.start();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming),
        streamingReply: _reply('一二三', '四'),
      );
      await _flushTail();
      // 流式回复已清空（null）：finalizing 必须沿用最后一次非空字数。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.finalizing),
        streamingReply: null,
      );
      await _flushTail();
      expect(port.payloads.last.text, '正在保存结果 · 正文 3 字 · 推理 1 字');
    });
  });

  group('串行化与 token 隔离', () {
    test('阻塞的 start Future 使 update 与 terminal 排队等待，避免先清理后启动', () async {
      await coordinator.start();
      final blockedStart = Completer<ChatForegroundCommandResult>();
      port.queuedResults.add(blockedStart.future);
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();
      expect(
        port.calls,
        containsAllInOrder(['ensureNotificationPermission', 'start']),
      );

      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming),
        streamingReply: _reply('你', ''),
      );
      coordinator.onStateChanged(
        snapshot: _snapshot(
          ChatGenerationPhase.succeeded,
          outcome: _outcomeFor(ChatGenerationPhase.succeeded),
        ),
        streamingReply: null,
      );
      await _flushTail();
      // start 未 ACK 前，update 与 remove 都不允许提前执行。
      expect(port.calls.where((c) => c == 'update'), isEmpty);
      expect(port.calls.where((c) => c == 'remove'), isEmpty);

      blockedStart.complete(const ChatForegroundCommandResult.accepted());
      await _flushTail();
      expect(port.calls, [
        'takePendingOpenConversation',
        'ensureNotificationPermission',
        'start',
        'update',
        'remove',
      ]);
    });

    test('旧 token 的定时器、动作、Future 与 terminal 不影响新 token', () async {
      await coordinator.start();
      // token 1：preparing → start。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing, generationId: 1),
        streamingReply: null,
      );
      await _flushTail();
      // 阻塞 token 1 的下一个 update 命令。
      final blockedUpdate = Completer<ChatForegroundCommandResult>();
      port.queuedResults.add(blockedUpdate.future);
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming, generationId: 1),
        streamingReply: _reply('一', ''),
      );
      await _flushTail();
      // 同阶段更新挂起尾缘定时器。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming, generationId: 1),
        streamingReply: _reply('二', ''),
      );
      final oldTimer = timers.pending.single;

      // token 2 启动：替换当前 context 并取消旧定时器。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing, generationId: 2),
        streamingReply: null,
      );
      await _flushTail();
      expect(oldTimer.cancelled, isTrue);

      // 迟到的旧定时器回调：context currency 校验拒绝，不产生任何命令。
      oldTimer.fire(force: true);
      // 阻塞的旧 update Future 完成：ACK 只写回旧 context，不影响新 token。
      blockedUpdate.complete(const ChatForegroundCommandResult.accepted());
      await _flushTail();
      expect(port.calls, [
        'takePendingOpenConversation',
        'ensureNotificationPermission',
        'start',
        'update',
        'ensureNotificationPermission',
        'start',
      ]);
      expect(port.payloads.last.token, 2);

      // 旧 token 的 stop 动作：stale 忽略。
      port.actionsController.add(
        const ChatGenerationStopRequested(token: 1, conversationId: 'conv-1'),
      );
      await _flushTail();
      expect(stopCalls, isEmpty);
      expect(diagnostics, contains('stale_native_action'));

      // 旧 token 的迟到 terminal：入口拒绝，不触发 remove/report。
      coordinator.onStateChanged(
        snapshot: _snapshot(
          ChatGenerationPhase.succeeded,
          generationId: 1,
          outcome: _outcomeFor(ChatGenerationPhase.succeeded),
        ),
        streamingReply: null,
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'remove'), isEmpty);
      expect(terminalNotifications.receipts, isEmpty);

      // 新 token 的后续 streaming 正常投递。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming, generationId: 2),
        streamingReply: _reply('三', ''),
      );
      await _flushTail();
      expect(port.payloads.last.token, 2);
    });

    test(
      'token1 terminal 入队后 token2 启动仍按 start1 cleanup1 report1 start2 顺序完成',
      () async {
        await coordinator.start();
        final blockedStart1 = Completer<ChatForegroundCommandResult>();
        port.queuedResults.add(blockedStart1.future);
        coordinator.onStateChanged(
          snapshot: _snapshot(ChatGenerationPhase.preparing, generationId: 1),
          streamingReply: null,
        );
        await _flushTail();

        // token1 的 terminal 在被阻塞的 start1 之后入队。
        coordinator.onStateChanged(
          snapshot: _snapshot(
            ChatGenerationPhase.succeeded,
            generationId: 1,
            outcome: _outcomeFor(ChatGenerationPhase.succeeded),
          ),
          streamingReply: null,
        );
        // token2 随即启动：新 token 不得取消已入队的 cleanup/report。
        coordinator.onStateChanged(
          snapshot: _snapshot(ChatGenerationPhase.preparing, generationId: 2),
          streamingReply: null,
        );
        await _flushTail();
        // start1 未完成前，整个 tail 都不允许推进。
        expect(port.calls.where((c) => c == 'start'), hasLength(1));
        expect(port.calls.where((c) => c == 'remove'), isEmpty);

        blockedStart1.complete(const ChatForegroundCommandResult.accepted());
        await _flushTail();
        // FIFO 顺序固定：start1 → cleanup1 → report1 → start2。
        expect(sharedLog, [
          'start:1',
          'remove',
          'report:succeeded:1',
          'start:2',
        ]);
      },
    );

    test('token1 ACK 迟到只修改 token1 context 不毒化 token2', () async {
      await coordinator.start();
      final lateFailingStart1 = Completer<ChatForegroundCommandResult>();
      port.queuedResults.add(lateFailingStart1.future);
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing, generationId: 1),
        streamingReply: null,
      );
      await _flushTail();

      // token2 在 token1 的 start ACK 尚未返回期间启动；start2 按 FIFO 排在
      // 被阻塞的 start1 之后，尚未执行。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing, generationId: 2),
        streamingReply: null,
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'start'), hasLength(1));
      expect(port.payloads.last.token, 1);

      // token1 的迟到 ACK 以失败收束：只标记 token1 自己的 context。
      lateFailingStart1.complete(
        const ChatForegroundCommandResult.unavailable(
          ChatForegroundFailureCode.startNotAllowed,
        ),
      );
      await _flushTail();
      expect(diagnostics.where((d) => d == 'start_not_allowed'), hasLength(1));
      // token1 失败后 token2 的 start 照常执行：未被毒化。
      expect(port.calls.where((c) => c == 'start'), hasLength(2));
      expect(port.payloads.last.token, 2);

      // token2 的 streaming 更新照常投递：未被 token1 的失败毒化。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming, generationId: 2),
        streamingReply: _reply('二', ''),
      );
      await _flushTail();
      expect(port.payloads.last.token, 2);
      expect(port.calls.where((c) => c == 'update'), ['update']);
    });
  });

  group('openConversation 回调兜底', () {
    test('回调抛错时记录固定诊断且不向 zone 泄漏', () async {
      final throwingCoordinator = ChatGenerationNotificationCoordinator(
        port: port,
        notificationSessionId: _notificationSessionId,
        terminalNotifications: terminalNotifications,
        stopGeneration: () async => stopCalls.add('stop'),
        openConversation: (_) => throw StateError('导航失败'),
        now: clock.call,
        timerFactory: timers.create,
        logDiagnostic: diagnostics.add,
      );
      addTearDown(throwingCoordinator.dispose);
      await throwingCoordinator.start();
      // warm 动作：回调抛错被兜底，只记固定诊断，不逃逸到 zone。
      port.actionsController.add(
        const ChatGenerationOpenConversationRequested('conv-warm'),
      );
      await _flushTail();
      expect(diagnostics, contains('open_conversation_failed'));
    });
  });

  group('stop 动作', () {
    test('重复的有效 stop 动作只调用一次 stopGeneration', () async {
      await coordinator.start();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();

      const stopAction = ChatGenerationStopRequested(
        token: 1,
        conversationId: 'conv-1',
      );
      port.actionsController.add(stopAction);
      port.actionsController.add(stopAction);
      await _flushTail();
      expect(stopCalls, ['stop']);

      // 进入 stopping 阶段后再次收到，同样不重复调用。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.stopping),
        streamingReply: null,
      );
      await _flushTail();
      port.actionsController.add(stopAction);
      await _flushTail();
      expect(stopCalls, ['stop']);
    });

    test('stop 动作本身不调用 remove，只有后续 terminal 快照才清理', () async {
      await coordinator.start();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();

      port.actionsController.add(
        const ChatGenerationStopRequested(token: 1, conversationId: 'conv-1'),
      );
      await _flushTail();
      expect(stopCalls, ['stop']);
      expect(port.calls.where((c) => c == 'remove'), isEmpty);

      // terminal（cancelled）到达后才有 remove；取消无收据、只清理。
      coordinator.onStateChanged(
        snapshot: _snapshot(
          ChatGenerationPhase.cancelled,
          outcome: _outcomeFor(ChatGenerationPhase.cancelled),
        ),
        streamingReply: null,
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'remove'), ['remove']);
      expect(terminalNotifications.receipts, isEmpty);
    });

    test('stopGeneration 抛错时记录固定诊断且不向 zone 泄漏，下一 token 仍可停止', () async {
      final throwingCoordinator = ChatGenerationNotificationCoordinator(
        port: port,
        notificationSessionId: _notificationSessionId,
        terminalNotifications: terminalNotifications,
        stopGeneration: () async => throw StateError('stop 失败'),
        openConversation: openedConversationIds.add,
        now: clock.call,
        timerFactory: timers.create,
        logDiagnostic: diagnostics.add,
      );
      addTearDown(throwingCoordinator.dispose);
      await throwingCoordinator.start();
      throwingCoordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();

      port.actionsController.add(
        const ChatGenerationStopRequested(token: 1, conversationId: 'conv-1'),
      );
      await _flushTail();
      // catch 兜底：异常不逃逸到 zone（本用例正常结束即证明），只记固定诊断。
      expect(diagnostics, contains('stop_failed'));

      // 下一 token：新 context 清空 stopInFlight，stop 不永久卡死。
      throwingCoordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing, generationId: 2),
        streamingReply: null,
      );
      await _flushTail();
      port.actionsController.add(
        const ChatGenerationStopRequested(token: 2, conversationId: 'conv-1'),
      );
      await _flushTail();
      expect(diagnostics.where((d) => d == 'stop_failed'), hasLength(2));
    });
  });

  group('平台失败 fail-open', () {
    test('start/update 失败将 token 标记不可用，不改变输入快照也不调用 stop', () async {
      await coordinator.start();
      port.queuedResults.add(
        Future.value(
          const ChatForegroundCommandResult.unavailable(
            ChatForegroundFailureCode.startNotAllowed,
          ),
        ),
      );
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'start'), ['start']);
      expect(diagnostics, contains('start_not_allowed'));

      // 后续 streaming 更新被抑制：不再产生任何命令。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming),
        streamingReply: _reply('你', ''),
      );
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming),
        streamingReply: _reply('你好', ''),
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'update'), isEmpty);
      expect(stopCalls, isEmpty);

      // 新 token：start 成功（队列为空时默认 accepted），update 失败同样标记不可用。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing, generationId: 2),
        streamingReply: null,
      );
      await _flushTail();
      port.queuedResults.add(
        Future.value(
          const ChatForegroundCommandResult.unavailable(
            ChatForegroundFailureCode.channelTimeout,
          ),
        ),
      );
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming, generationId: 2),
        streamingReply: _reply('一', ''),
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'update'), ['update']);
      expect(diagnostics, contains('command_timeout'));
      // channelTimeout 不判死通道：后续 streaming 更新继续投递。
      // 同阶段更新受 1s 尾缘节流约束，推进时钟使本次投递立即发生。
      clock.advance(chatGenerationNotificationUpdateInterval);
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming, generationId: 2),
        streamingReply: _reply('二', ''),
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'update').length, 2);
      expect(stopCalls, isEmpty);
    });

    test('token 不可用后 terminal 仍执行 remove 清理并报告收据，不提前跳过', () async {
      await coordinator.start();
      final cases = <(ChatGenerationPhase, ChatGenerationTerminalKind)>[
        (ChatGenerationPhase.succeeded, ChatGenerationTerminalKind.succeeded),
        (ChatGenerationPhase.failed, ChatGenerationTerminalKind.failed),
      ];
      for (final (index, c) in cases.indexed) {
        final token = index + 1;
        port.queuedResults.add(
          Future.value(
            const ChatForegroundCommandResult.unavailable(
              ChatForegroundFailureCode.serviceUnavailable,
            ),
          ),
        );
        coordinator.onStateChanged(
          snapshot: _snapshot(
            ChatGenerationPhase.preparing,
            generationId: token,
          ),
          streamingReply: null,
        );
        await _flushTail();
        coordinator.onStateChanged(
          snapshot: _snapshot(
            c.$1,
            generationId: token,
            outcome: _outcomeFor(c.$1),
          ),
          streamingReply: null,
        );
        await _flushTail();
        expect(
          port.calls.where((x) => x == 'remove').length,
          index + 1,
          reason: 'token $token 应各自清理一次',
        );
        expect(terminalNotifications.receipts.last.terminalKind, c.$2);
        expect(terminalNotifications.receipts.last.generationId, token);
        expect(stopCalls, isEmpty);
      }
    });

    test('start 失败后不自动重试，同一 coordinator 中下一新 token 仍可重新 start', () async {
      await coordinator.start();
      port.queuedResults.add(
        Future.value(
          const ChatForegroundCommandResult.unavailable(
            ChatForegroundFailureCode.startNotAllowed,
          ),
        ),
      );
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing, generationId: 1),
        streamingReply: null,
      );
      await _flushTail();

      // 同 token 再次 preparing / streaming：不自动重试 start。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing, generationId: 1),
        streamingReply: null,
      );
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming, generationId: 1),
        streamingReply: _reply('一', ''),
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'start').length, 1);

      // 下一新 token：重新允许 start。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing, generationId: 2),
        streamingReply: null,
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'start').length, 2);
      expect(port.payloads.last.token, 2);
    });

    test('channelTimeout 是假阴性：不判死通道，后续 update 与 terminal 清理照常', () async {
      await coordinator.start();
      port.queuedResults.add(
        Future.value(
          const ChatForegroundCommandResult.unavailable(
            ChatForegroundFailureCode.channelTimeout,
          ),
        ),
      );
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();
      expect(diagnostics, contains('command_timeout'));
      // channelTimeout 后 update 仍投递：原生可能已接受 start（慢设备 promotion）。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming),
        streamingReply: _reply('一', ''),
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'update'), ['update']);
      // terminal 清理照常执行。
      coordinator.onStateChanged(
        snapshot: _snapshot(
          ChatGenerationPhase.succeeded,
          outcome: _outcomeFor(ChatGenerationPhase.succeeded),
        ),
        streamingReply: null,
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'remove'), ['remove']);
    });

    test('已入队的 update 在 timeout 到达后执行时被跳过，不再向已停止的服务补发', () async {
      await coordinator.start();
      // 阻塞 start，使后续 update 排队等待。
      final blockedStart = Completer<ChatForegroundCommandResult>();
      port.queuedResults.add(blockedStart.future);
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming),
        streamingReply: _reply('你', ''),
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'update'), isEmpty);

      // start 阻塞期间原生已超时：Kotlin 移除 ongoing 并停止服务。
      port.actionsController.add(
        const ChatGenerationForegroundTimedOut(
          token: 1,
          conversationId: 'conv-1',
        ),
      );
      await _flushTail();

      blockedStart.complete(const ChatForegroundCommandResult.accepted());
      await _flushTail();
      // 已入队的 update 执行时读到 timedOut：不再补发。
      expect(port.calls.where((c) => c == 'update'), isEmpty);
    });
  });

  group('终态通知接入', () {
    test('成功先清理 ongoing 再报告终态', () async {
      await coordinator.start();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();
      coordinator.onStateChanged(
        snapshot: _snapshot(
          ChatGenerationPhase.succeeded,
          outcome: _outcomeFor(ChatGenerationPhase.succeeded),
        ),
        streamingReply: null,
      );
      await _flushTail();

      // 串行 cleanup 后 report 是有意权衡：避免 Android 同时展示 ongoing 与终态。
      expect(sharedLog.where((e) => e == 'remove' || e.startsWith('report:')), [
        'remove',
        'report:succeeded:1',
      ]);
      final receipt = terminalNotifications.receipts.single;
      expect(receipt.notificationSessionId, _notificationSessionId);
      expect(receipt.generationId, 1);
      expect(receipt.conversationId, 'conv-1');
    });

    test(
      '三次 cleanup channel timeout 与退避使 report 最晚在 cleanup 开始后 7 秒执行',
      () async {
        await coordinator.start();
        coordinator.onStateChanged(
          snapshot: _snapshot(ChatGenerationPhase.preparing),
          streamingReply: null,
        );
        await _flushTail();

        // 三次 remove 各自模拟 2 秒 channel timeout 后才以失败收束（fake 时间记账，
        // 不真实等待）。200ms/800ms 退避经手动定时器触发。
        final hangingRemoves = List.generate(
          3,
          (_) => Completer<ChatForegroundCommandResult>(),
        );
        for (final completer in hangingRemoves) {
          port.queuedResults.add(completer.future);
        }
        final cleanupStart = clock.current;
        coordinator.onStateChanged(
          snapshot: _snapshot(
            ChatGenerationPhase.succeeded,
            outcome: _outcomeFor(ChatGenerationPhase.succeeded),
          ),
          streamingReply: null,
        );
        await _flushTail();
        expect(port.calls.where((c) => c == 'remove'), hasLength(1));
        // 第一次 remove 尚在途：report 不得提前执行。
        expect(terminalNotifications.receipts, isEmpty);

        const channelTimeout = Duration(seconds: 2);
        for (var i = 0; i < hangingRemoves.length; i++) {
          clock.advance(channelTimeout);
          hangingRemoves[i].complete(
            const ChatForegroundCommandResult.unavailable(
              ChatForegroundFailureCode.channelTimeout,
            ),
          );
          await _flushTail();
          if (i < hangingRemoves.length - 1) {
            final backoff = chatGenerationNotificationCleanupRetryDelays[i + 1];
            expect(timers.pending.single.duration, backoff);
            clock.advance(backoff);
            timers.fireNext();
            await _flushTail();
          }
        }

        // 上界 = 3 × 2s + 200ms + 800ms = 7s；耗尽后才 report。
        expect(
          clock.current.difference(cleanupStart),
          const Duration(seconds: 7),
        );
        expect(
          terminalNotifications.receipts.single.terminalKind,
          ChatGenerationTerminalKind.succeeded,
        );
        expect(diagnostics, contains('cleanup_retry_exhausted'));
        expect(timers.pending, isEmpty);
      },
    );

    test('空回复失败和持久化失败都清理 ongoing', () async {
      await coordinator.start();
      final cases = <(ChatGenerationPhase, ChatGenerationTerminalKind)>[
        (ChatGenerationPhase.emptyReply, ChatGenerationTerminalKind.emptyReply),
        (
          ChatGenerationPhase.persistenceFailed,
          ChatGenerationTerminalKind.persistenceFailed,
        ),
      ];
      for (final (index, c) in cases.indexed) {
        final token = index + 1;
        coordinator.onStateChanged(
          snapshot: _snapshot(
            ChatGenerationPhase.preparing,
            generationId: token,
          ),
          streamingReply: null,
        );
        await _flushTail();
        coordinator.onStateChanged(
          snapshot: _snapshot(
            c.$1,
            generationId: token,
            outcome: _outcomeFor(c.$1),
          ),
          streamingReply: null,
        );
        await _flushTail();
      }
      expect(port.calls.where((c) => c == 'remove'), hasLength(2));
      expect(
        terminalNotifications.receipts.map((r) => r.terminalKind),
        cases.map((c) => c.$2),
      );
    });

    test('取消只清理不报告', () async {
      await coordinator.start();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();
      coordinator.onStateChanged(
        snapshot: _snapshot(
          ChatGenerationPhase.cancelled,
          outcome: _outcomeFor(ChatGenerationPhase.cancelled),
        ),
        streamingReply: null,
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'remove'), ['remove']);
      expect(terminalNotifications.receipts, isEmpty);
    });

    test('中间重试不清理也不报告', () async {
      await coordinator.start();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.retryWaiting, attempt: 2),
        streamingReply: null,
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'remove'), isEmpty);
      expect(terminalNotifications.receipts, isEmpty);
    });

    test('成功终态使用完整 outcome 计数而 timeout 使用 context 最后安全计数', () async {
      await coordinator.start();
      // token1：流式计数停在 3/1，成功终态从完整 outcome 重算出 5/2。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing, generationId: 1),
        streamingReply: null,
      );
      await _flushTail();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming, generationId: 1),
        streamingReply: _reply('一二三', '四'),
      );
      await _flushTail();
      coordinator.onStateChanged(
        snapshot: _snapshot(
          ChatGenerationPhase.succeeded,
          generationId: 1,
          outcome: const ChatGenerationSuccess(
            generationId: 1,
            attempt: 1,
            content: '一二三四五',
            reasoningContent: '六七',
          ),
        ),
        streamingReply: null,
      );
      await _flushTail();
      final successReceipt = terminalNotifications.receipts.single;
      expect(successReceipt.terminalKind, ChatGenerationTerminalKind.succeeded);
      expect(successReceipt.contentCount, 5);
      expect(successReceipt.reasoningCount, 2);

      // token2：流式计数 3/1 后保护超时，收据沿用最后安全计数而非重算。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing, generationId: 2),
        streamingReply: null,
      );
      await _flushTail();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming, generationId: 2),
        streamingReply: _reply('一二三', '四'),
      );
      await _flushTail();
      port.actionsController.add(
        const ChatGenerationForegroundTimedOut(
          token: 2,
          conversationId: 'conv-1',
        ),
      );
      await _flushTail();
      final timeoutReceipt = terminalNotifications.receipts.last;
      expect(
        timeoutReceipt.terminalKind,
        ChatGenerationTerminalKind.foregroundProtectionTimedOut,
      );
      expect(timeoutReceipt.generationId, 2);
      expect(timeoutReceipt.contentCount, 3);
      expect(timeoutReceipt.reasoningCount, 1);
    });

    test('保护超时只报告且不调用 remove 或停止生成', () async {
      await coordinator.start();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();

      port.actionsController.add(
        const ChatGenerationForegroundTimedOut(
          token: 1,
          conversationId: 'conv-1',
        ),
      );
      await _flushTail();

      // Kotlin 发 callback 前已自行移除 ongoing：Dart 侧不再 remove，避免重入；
      // timeout 不修改生成状态，绝不触发 stop。
      final receipt = terminalNotifications.receipts.single;
      expect(
        receipt.terminalKind,
        ChatGenerationTerminalKind.foregroundProtectionTimedOut,
      );
      expect(
        receipt.failureKind,
        ChatGenerationTerminalFailureKind.foregroundProtection,
      );
      expect(port.calls.where((c) => c == 'remove'), isEmpty);
      expect(stopCalls, isEmpty);
      expect(diagnostics, contains('platform_timeout'));
    });

    test('保护超时后真正终态仍报告且不重复清理', () async {
      await coordinator.start();
      // token1：超时后 succeeded —— 报告两次（timeout + 真正终态）、零次 remove。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing, generationId: 1),
        streamingReply: null,
      );
      await _flushTail();
      port.actionsController.add(
        const ChatGenerationForegroundTimedOut(
          token: 1,
          conversationId: 'conv-1',
        ),
      );
      await _flushTail();
      coordinator.onStateChanged(
        snapshot: _snapshot(
          ChatGenerationPhase.succeeded,
          generationId: 1,
          outcome: _outcomeFor(ChatGenerationPhase.succeeded),
        ),
        streamingReply: null,
      );
      await _flushTail();
      expect(terminalNotifications.receipts.map((r) => r.terminalKind), [
        ChatGenerationTerminalKind.foregroundProtectionTimedOut,
        ChatGenerationTerminalKind.succeeded,
      ]);
      expect(port.calls.where((c) => c == 'remove'), isEmpty);

      // token2：超时后 cancelled —— 收据为 null，完全 no-op。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing, generationId: 2),
        streamingReply: null,
      );
      await _flushTail();
      port.actionsController.add(
        const ChatGenerationForegroundTimedOut(
          token: 2,
          conversationId: 'conv-1',
        ),
      );
      await _flushTail();
      final receiptsBeforeCancel = terminalNotifications.receipts.length;
      coordinator.onStateChanged(
        snapshot: _snapshot(
          ChatGenerationPhase.cancelled,
          generationId: 2,
          outcome: _outcomeFor(ChatGenerationPhase.cancelled),
        ),
        streamingReply: null,
      );
      await _flushTail();
      expect(terminalNotifications.receipts.length, receiptsBeforeCancel);
      expect(port.calls.where((c) => c == 'remove'), isEmpty);
    });

    test('terminal report 失败不毒化 coordinator', () async {
      terminalNotifications.throwOnReport = true;
      await coordinator.start();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();
      coordinator.onStateChanged(
        snapshot: _snapshot(
          ChatGenerationPhase.succeeded,
          outcome: _outcomeFor(ChatGenerationPhase.succeeded),
        ),
        streamingReply: null,
      );
      await _flushTail();

      // cleanup 照常执行、report 被调用且契约外抛错被兜底为固定诊断。
      expect(port.calls.where((c) => c == 'remove'), ['remove']);
      expect(terminalNotifications.receipts, hasLength(1));
      expect(diagnostics, contains('terminal_report_failed'));

      // 后续 generation 完全不受影响：start 正常、report 正常送达。
      terminalNotifications.throwOnReport = false;
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing, generationId: 2),
        streamingReply: null,
      );
      await _flushTail();
      coordinator.onStateChanged(
        snapshot: _snapshot(
          ChatGenerationPhase.succeeded,
          generationId: 2,
          outcome: _outcomeFor(ChatGenerationPhase.succeeded, generationId: 2),
        ),
        streamingReply: null,
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'start'), hasLength(2));
      expect(port.calls.where((c) => c == 'remove'), hasLength(2));
      expect(terminalNotifications.receipts.last.generationId, 2);
    });

    test('尚未入队的旧 token terminal 和 timeout 被拒绝', () async {
      await coordinator.start();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing, generationId: 1),
        streamingReply: null,
      );
      await _flushTail();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing, generationId: 2),
        streamingReply: null,
      );
      await _flushTail();

      // 旧 token1 的迟到 terminal 快照：入口拒绝，不清理也不报告。
      coordinator.onStateChanged(
        snapshot: _snapshot(
          ChatGenerationPhase.succeeded,
          generationId: 1,
          outcome: _outcomeFor(ChatGenerationPhase.succeeded),
        ),
        streamingReply: null,
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'remove'), isEmpty);
      expect(terminalNotifications.receipts, isEmpty);

      // 旧 token1 的 timeout 动作：stale 忽略，不产生收据。
      port.actionsController.add(
        const ChatGenerationForegroundTimedOut(
          token: 1,
          conversationId: 'conv-1',
        ),
      );
      await _flushTail();
      expect(terminalNotifications.receipts, isEmpty);
      expect(diagnostics, contains('stale_native_action'));
    });

    test('终态时刻的抑制决策被冻结并随 report 传递', () async {
      final suppressingCoordinator = ChatGenerationNotificationCoordinator(
        port: port,
        notificationSessionId: _notificationSessionId,
        terminalNotifications: terminalNotifications,
        stopGeneration: () async => stopCalls.add('stop'),
        openConversation: openedConversationIds.add,
        isTerminalSuppressed: (conversationId) => true,
        now: clock.call,
        timerFactory: timers.create,
        logDiagnostic: diagnostics.add,
      );
      addTearDown(suppressingCoordinator.dispose);
      await suppressingCoordinator.start();
      suppressingCoordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();
      suppressingCoordinator.onStateChanged(
        snapshot: _snapshot(
          ChatGenerationPhase.succeeded,
          outcome: _outcomeFor(ChatGenerationPhase.succeeded),
        ),
        streamingReply: null,
      );
      await _flushTail();
      // cleanup 照常执行；report 携带终态时刻冻结的抑制决策 true。
      expect(port.calls.where((c) => c == 'remove'), ['remove']);
      expect(
        terminalNotifications.receipts.single.terminalKind,
        ChatGenerationTerminalKind.succeeded,
      );
      expect(terminalNotifications.reportsWithSuppression, [true]);
    });

    test('timeout 收据同样冻结终态时刻的抑制决策', () async {
      final suppressingCoordinator = ChatGenerationNotificationCoordinator(
        port: port,
        notificationSessionId: _notificationSessionId,
        terminalNotifications: terminalNotifications,
        stopGeneration: () async => stopCalls.add('stop'),
        openConversation: openedConversationIds.add,
        isTerminalSuppressed: (conversationId) => true,
        now: clock.call,
        timerFactory: timers.create,
        logDiagnostic: diagnostics.add,
      );
      addTearDown(suppressingCoordinator.dispose);
      await suppressingCoordinator.start();
      suppressingCoordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();
      port.actionsController.add(
        const ChatGenerationForegroundTimedOut(
          token: 1,
          conversationId: 'conv-1',
        ),
      );
      await _flushTail();
      expect(
        terminalNotifications.receipts.single.terminalKind,
        ChatGenerationTerminalKind.foregroundProtectionTimedOut,
      );
      expect(terminalNotifications.reportsWithSuppression, [true]);
    });
  });

  group('平台超时的 ongoing 抑制', () {
    test('平台超时抑制后续 streaming 更新且不重新启动', () async {
      await coordinator.start();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming),
        streamingReply: _reply('你', ''),
      );
      await _flushTail();
      // 挂起一个尾缘定时器。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming),
        streamingReply: _reply('你好', ''),
      );
      expect(timers.pending, hasLength(1));

      port.actionsController.add(
        const ChatGenerationForegroundTimedOut(
          token: 1,
          conversationId: 'conv-1',
        ),
      );
      await _flushTail();
      expect(timers.pending, isEmpty);
      expect(diagnostics, contains('platform_timeout'));

      // 后续 streaming 更新被抑制。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming),
        streamingReply: _reply('你好呀', ''),
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'update').length, 1);

      // 同 token 再次 preparing：不得重新 start。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'start').length, 1);
    });
  });

  group('terminal 清理', () {
    test('terminal ACK 失败按 200ms/800ms 重试恰好 3 次后停止调度，再报告收据', () async {
      await coordinator.start();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();
      port.queuedResults.addAll([
        Future.value(
          const ChatForegroundCommandResult.unavailable(
            ChatForegroundFailureCode.serviceUnavailable,
          ),
        ),
        Future.value(
          const ChatForegroundCommandResult.unavailable(
            ChatForegroundFailureCode.serviceUnavailable,
          ),
        ),
        Future.value(
          const ChatForegroundCommandResult.unavailable(
            ChatForegroundFailureCode.serviceUnavailable,
          ),
        ),
      ]);
      coordinator.onStateChanged(
        snapshot: _snapshot(
          ChatGenerationPhase.succeeded,
          outcome: _outcomeFor(ChatGenerationPhase.succeeded),
        ),
        streamingReply: null,
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'remove').length, 1);
      // cleanup 未收束前 report 不执行。
      expect(terminalNotifications.receipts, isEmpty);
      expect(timers.pending.single.duration, const Duration(milliseconds: 200));

      timers.fireNext();
      await _flushTail();
      expect(port.calls.where((c) => c == 'remove').length, 2);
      expect(timers.pending.single.duration, const Duration(milliseconds: 800));

      timers.fireNext();
      await _flushTail();
      expect(port.calls.where((c) => c == 'remove').length, 3);
      expect(timers.pending, isEmpty);
      expect(diagnostics, contains('cleanup_retry_exhausted'));
      // 耗尽后仍 report：cleanup 失败不阻止真正终态通知。
      expect(
        terminalNotifications.receipts.single.terminalKind,
        ChatGenerationTerminalKind.succeeded,
      );
    });

    test('terminal 入队后、remove 执行前收到 timeout：跳过 remove、只报告终态收据', () async {
      await coordinator.start();
      final blockedStart = Completer<ChatForegroundCommandResult>();
      port.queuedResults.add(blockedStart.future);
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();

      // 终态快照在 start 阻塞期间到达：terminal op 排在 start 之后。
      coordinator.onStateChanged(
        snapshot: _snapshot(
          ChatGenerationPhase.succeeded,
          outcome: _outcomeFor(ChatGenerationPhase.succeeded),
        ),
        streamingReply: null,
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'remove'), isEmpty);

      // start 阻塞期间原生已超时：Kotlin 自行移除 ongoing 并停止服务。
      port.actionsController.add(
        const ChatGenerationForegroundTimedOut(
          token: 1,
          conversationId: 'conv-1',
        ),
      );
      await _flushTail();

      // start ACK 后 terminal op 执行：执行时读到 timedOut，跳过 remove。
      blockedStart.complete(const ChatForegroundCommandResult.accepted());
      await _flushTail();
      expect(port.calls.where((c) => c == 'remove'), isEmpty);
      expect(terminalNotifications.receipts.map((r) => r.terminalKind), [
        ChatGenerationTerminalKind.succeeded,
      ]);
      expect(diagnostics, contains('platform_timeout'));
    });
  });

  group('生命周期', () {
    test('dispose 取消定时器与订阅，迟到的完成被忽略', () async {
      await coordinator.start();
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing),
        streamingReply: null,
      );
      await _flushTail();
      // 阻塞下一个 update 命令。
      final blockedUpdate = Completer<ChatForegroundCommandResult>();
      port.queuedResults.add(blockedUpdate.future);
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming),
        streamingReply: _reply('你', ''),
      );
      await _flushTail();
      // 同阶段更新挂起尾缘定时器。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming),
        streamingReply: _reply('你好', ''),
      );
      final pendingTimer = timers.pending.single;

      coordinator.dispose();
      expect(pendingTimer.cancelled, isTrue);
      expect(timers.pending, isEmpty);
      final callsBefore = port.calls.length;

      // 定时器即使强制触发也无副作用。
      pendingTimer.fire(force: true);
      // 订阅已取消：迟到动作不再触达。
      port.actionsController.add(
        const ChatGenerationStopRequested(token: 1, conversationId: 'conv-1'),
      );
      // 阻塞中的命令完成：dispose 后忽略结果。
      blockedUpdate.complete(const ChatForegroundCommandResult.accepted());
      await _flushTail();
      expect(port.calls.length, callsBefore);
      expect(stopCalls, isEmpty);

      // dispose 后的状态变化不再产生命令。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing, generationId: 2),
        streamingReply: null,
      );
      await _flushTail();
      expect(port.calls.length, callsBefore);
    });
  });
}

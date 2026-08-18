import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/composition/chat_generation_notification_coordinator.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_state.dart';

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

/// 可手动推进的时钟，配合节流间隔判定。
final class TestClock {
  DateTime current = DateTime(2026, 1, 1);

  DateTime call() => current;

  void advance(Duration duration) => current = current.add(duration);
}

/// 确定性端口 fake：命令调用同步记录到 [calls]，结果按 [queuedResults] 顺序返回，
/// 队列为空时默认 accepted。
final class FakeChatGenerationForegroundService
    implements ChatGenerationForegroundServicePort {
  final actionsController =
      StreamController<ChatGenerationForegroundAction>.broadcast();
  final calls = <String>[];
  final payloads = <ChatGenerationForegroundPayload>[];
  final queuedResults = Queue<Future<ChatForegroundCommandResult>>();

  /// 待打开的冷启动会话 ID；[takePendingOpenConversation] 返回它。
  String? pendingOpenConversationId;

  /// 非 null 时阻塞 [takePendingOpenConversation]，用于验证订阅先于第一个 await。
  Completer<void>? takePendingGate;

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
    if (payload != null) payloads.add(payload);
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
  Future<ChatForegroundCommandResult> fail(
    ChatGenerationForegroundPayload payload,
  ) => _record('fail', payload);

  @override
  Future<String?> takePendingOpenConversation() async {
    calls.add('takePendingOpenConversation');
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

void main() {
  late FakeChatGenerationForegroundService port;
  late TestTimerScheduler timers;
  late TestClock clock;
  late ChatGenerationNotificationCoordinator coordinator;
  final diagnostics = <String>[];
  final stopCalls = <String>[];
  final openedConversationIds = <String>[];

  setUp(() {
    port = FakeChatGenerationForegroundService();
    timers = TestTimerScheduler();
    clock = TestClock();
    diagnostics.clear();
    stopCalls.clear();
    openedConversationIds.clear();
    coordinator = ChatGenerationNotificationCoordinator(
      port: port,
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
      // 幂等：重复 start 不再取走。
      await coordinator.start();
      expect(
        port.calls.where((c) => c == 'takePendingOpenConversation').length,
        1,
      );
    });

    test('openConversationRequested 动作转发给注入回调', () async {
      await coordinator.start();
      port.actionsController.add(
        const ChatGenerationOpenConversationRequested('conv-9'),
      );
      await _flushTail();
      expect(openedConversationIds, ['conv-9']);
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

      // token 2 启动：重置 per-token 状态并取消旧定时器。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.preparing, generationId: 2),
        streamingReply: null,
      );
      await _flushTail();
      expect(oldTimer.cancelled, isTrue);

      // 迟到的旧定时器回调：token 校验拒绝，不产生任何命令。
      oldTimer.fire(force: true);
      // 阻塞的旧 update Future 完成：token 校验拒绝，不再产生命令。
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

      // 旧 token 的迟到 terminal：丢弃，不触发 remove。
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

      // 新 token 的后续 streaming 正常投递。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming, generationId: 2),
        streamingReply: _reply('三', ''),
      );
      await _flushTail();
      expect(port.payloads.last.token, 2);
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

      // terminal（cancelled）到达后才有 remove。
      coordinator.onStateChanged(
        snapshot: _snapshot(
          ChatGenerationPhase.cancelled,
          outcome: _outcomeFor(ChatGenerationPhase.cancelled),
        ),
        streamingReply: null,
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'remove'), ['remove']);
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
      // 不可用后同一 token 的 streaming 更新被抑制。
      coordinator.onStateChanged(
        snapshot: _snapshot(ChatGenerationPhase.streaming, generationId: 2),
        streamingReply: _reply('二', ''),
      );
      await _flushTail();
      expect(port.calls.where((c) => c == 'update').length, 1);
      expect(stopCalls, isEmpty);
    });

    test('token 不可用后 terminal 仍执行 remove/fail 清理，不提前跳过', () async {
      await coordinator.start();
      final cases = <(ChatGenerationPhase, ChatGenerationOutcome, String)>[
        (
          ChatGenerationPhase.succeeded,
          _outcomeFor(ChatGenerationPhase.succeeded),
          'remove',
        ),
        (
          ChatGenerationPhase.failed,
          _outcomeFor(ChatGenerationPhase.failed),
          'fail',
        ),
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
          snapshot: _snapshot(c.$1, generationId: token, outcome: c.$2),
          streamingReply: null,
        );
        await _flushTail();
        expect(
          port.calls.where((x) => x == c.$3).length,
          1,
          reason: '${c.$3} 应恰好清理一次',
        );
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
  });

  group('平台超时', () {
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

    test('超时后 success/cancel 调用 remove、failure 调用 fail', () async {
      await coordinator.start();
      final cases = <(ChatGenerationPhase, String)>[
        (ChatGenerationPhase.succeeded, 'remove'),
        (ChatGenerationPhase.cancelled, 'remove'),
        (ChatGenerationPhase.failed, 'fail'),
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
        port.actionsController.add(
          ChatGenerationForegroundTimedOut(
            token: token,
            conversationId: 'conv-1',
          ),
        );
        await _flushTail();
        coordinator.onStateChanged(
          snapshot: _snapshot(
            c.$1,
            generationId: token,
            outcome: _outcomeFor(c.$1, generationId: token),
          ),
          streamingReply: null,
        );
        await _flushTail();
      }
      // 三个 token 各自只清理一次：remove 两次、fail 一次，不跨 token 泄漏。
      expect(port.calls.where((x) => x == 'remove').length, 2);
      expect(port.calls.where((x) => x == 'fail').length, 1);
      expect(stopCalls, isEmpty);
    });
  });

  group('terminal 清理', () {
    test('terminal ACK 失败按 200ms/800ms 重试恰好 3 次后停止调度', () async {
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

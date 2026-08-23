import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/attention/app_attention_state.dart';
import 'package:oh_my_llm/app/notifications/chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/app/notifications/default_chat_generation_terminal_notifications.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_terminal_notification.dart';

/// 固定测试进程会话 ID（与计划 5.2 预核对向量一致）。
const _session = '000102030405060708090a0b0c0d0e0f';

/// 可控 fake adapter：记录调用、支持排队 initialize/show 故障与手动激活。
final class FakeTerminalNotificationAdapter
    implements ChatGenerationTerminalNotificationAdapter {
  final activationsController =
      StreamController<ChatGenerationNotificationActivation>();

  final shownNotifications = <ChatGenerationSafeNotification>[];
  var initializeCallCount = 0;
  var disposeCallCount = 0;
  ChatGenerationNotificationActivation? pendingActivation;

  /// 非空时 initialize 等待该 completer，用于「初始化完成前 report」时序。
  Completer<void>? initializeGate;

  /// 非空时 initialize 抛出该错误。
  Object? initializeError;

  /// 非空时 show 抛出该错误（记录后抛出）。
  Object? showError;

  /// 非空时 show 等待该 completer，用于构造并发 in-flight 报告。
  Completer<void>? showGate;

  @override
  Stream<ChatGenerationNotificationActivation> get activations =>
      activationsController.stream;

  @override
  Future<void> initialize() async {
    initializeCallCount += 1;
    final gate = initializeGate;
    if (gate != null) await gate.future;
    final error = initializeError;
    if (error != null) throw error;
  }

  @override
  Future<void> show(ChatGenerationSafeNotification notification) async {
    shownNotifications.add(notification);
    final gate = showGate;
    if (gate != null) await gate.future;
    final error = showError;
    if (error != null) throw error;
  }

  @override
  Future<ChatGenerationNotificationActivation?> takePendingActivation() async {
    final pending = pendingActivation;
    pendingActivation = null;
    return pending;
  }

  @override
  Future<void> dispose() async {
    disposeCallCount += 1;
  }

  /// 手动投递一次 warm 激活。
  void emit(ChatGenerationNotificationActivation activation) {
    activationsController.add(activation);
  }
}

/// 深模块测试环境：集中持有可变注入与调用记录。
final class ModuleHarness {
  ModuleHarness({
    AppAttentionState? attention,
    this.activeConversationId = 'conv-2',
  }) : attention =
           attention ??
           AppAttentionState(
             lifecycleState: AppLifecycleState.resumed,
             windowFocused: true,
             location: Uri(path: '/chat'),
           );

  final adapter = FakeTerminalNotificationAdapter();

  /// 当前注意力快照（report 时读取；测试内可变）。
  AppAttentionState attention;

  /// 当前可见会话（仅路由为 /chat 且 attentive 时读取）。
  String activeConversationId;
  int activeConversationReads = 0;

  /// 会话存在性依据的活列表（导航帧读取）。
  final existingConversations = <String>{};

  /// openChat 调用记录（参数为 null 表示回退聊天根页）。
  final openChatCalls = <String?>[];
  var openChatShouldThrow = false;

  var restoreHostCallCount = 0;
  Future<void> Function() restoreHostImpl = () async {};
  var restoreHostShouldThrow = false;

  /// 固定分类诊断记录（不插值任何 payload/会话 ID/异常文本）。
  final diagnostics = <String>[];

  DefaultChatGenerationTerminalNotifications build() {
    return DefaultChatGenerationTerminalNotifications(
      adapter: adapter,
      readAttention: () => attention,
      readActiveConversationId: () {
        activeConversationReads += 1;
        return activeConversationId;
      },
      conversationExists: existingConversations.contains,
      restoreHost: () async {
        restoreHostCallCount += 1;
        await restoreHostImpl();
        if (restoreHostShouldThrow) {
          throw StateError('restore failed');
        }
      },
      openChat: (conversationId) {
        openChatCalls.add(conversationId);
        if (openChatShouldThrow) throw StateError('navigation failed');
      },
      logDiagnostic: diagnostics.add,
    );
  }
}

/// 组装收据；默认值只在 succeeded 下配对合法。
ChatGenerationTerminalReceipt _receipt({
  int generationId = 7,
  String conversationId = 'conv-1',
  ChatGenerationTerminalKind terminalKind =
      ChatGenerationTerminalKind.succeeded,
  int contentCount = 12,
  int reasoningCount = 3,
  ChatGenerationTerminalFailureKind failureKind =
      ChatGenerationTerminalFailureKind.none,
}) {
  return ChatGenerationTerminalReceipt(
    notificationSessionId: _session,
    generationId: generationId,
    conversationId: conversationId,
    terminalKind: terminalKind,
    contentCount: contentCount,
    reasoningCount: reasoningCount,
    failureKind: failureKind,
  );
}

/// 组装一次激活（默认对应 generation 7 的 succeeded 事件）。
ChatGenerationNotificationActivation _activation({
  String eventKey = 'v1:$_session:7:succeeded',
  String conversationId = 'conv-1',
}) {
  return ChatGenerationNotificationActivation(
    eventKey: eventKey,
    conversationId: conversationId,
  );
}

/// 排空微任务直到 [condition] 满足（等待可观察完成条件，不用固定 delay；
/// 帧内测试只让出微任务，不推进帧/时间）。
Future<void> untilInMicrotasks(bool Function() condition) async {
  var rounds = 0;
  while (!condition() && rounds < 200) {
    await null;
    rounds += 1;
  }
  expect(condition(), isTrue, reason: '微任务排空后条件仍未满足');
}

void main() {
  group('report 抑制与去重', () {
    test('前台聚焦且查看对应会话时抑制通知', () async {
      // 默认 harness：resumed + focused + /chat + 活动会话 conv-1。
      final harness = ModuleHarness(activeConversationId: 'conv-1');
      final module = harness.build();
      addTearDown(module.dispose);

      await module.report(_receipt(conversationId: 'conv-1'));
      expect(harness.adapter.shownNotifications, isEmpty);
      // 抑制不产生任何平台调用，也不记失败诊断。
      expect(harness.diagnostics, isEmpty);
    });

    test('查看其他会话时展示通知', () async {
      final harness = ModuleHarness(activeConversationId: 'conv-2');
      final module = harness.build();
      addTearDown(module.dispose);

      await module.report(_receipt(conversationId: 'conv-1'));
      expect(harness.adapter.shownNotifications, hasLength(1));
    });

    test('非聊天页面时展示通知', () async {
      final harness = ModuleHarness(
        attention: AppAttentionState(
          lifecycleState: AppLifecycleState.resumed,
          windowFocused: true,
          location: Uri(path: '/history'),
        ),
        activeConversationId: 'conv-1',
      );
      final module = harness.build();
      addTearDown(module.dispose);

      await module.report(_receipt(conversationId: 'conv-1'));
      expect(harness.adapter.shownNotifications, hasLength(1));
      // 计划 3.2：仅在路由为 /chat 时才读取 activeConversationId。
      expect(harness.activeConversationReads, 0);
    });

    test('Windows 窗口失焦时展示通知', () async {
      final harness = ModuleHarness(
        attention: AppAttentionState(
          lifecycleState: AppLifecycleState.resumed,
          windowFocused: false,
          location: Uri(path: '/chat'),
        ),
        activeConversationId: 'conv-1',
      );
      final module = harness.build();
      addTearDown(module.dispose);

      await module.report(_receipt(conversationId: 'conv-1'));
      expect(harness.adapter.shownNotifications, hasLength(1));
    });

    test('detached 初值在首个真实注意力快照前选择展示', () async {
      // 启动初值：detached + 未聚焦 + 空 Uri；即使活动会话匹配也选择展示
      // （可能多发、不能漏发）。
      final harness = ModuleHarness(
        attention: AppAttentionState.initial,
        activeConversationId: 'conv-1',
      );
      final module = harness.build();
      addTearDown(module.dispose);

      await module.report(_receipt(conversationId: 'conv-1'));
      expect(harness.adapter.shownNotifications, hasLength(1));
      expect(harness.activeConversationReads, 0); // 非 attentive 不读取。
    });

    test('同一收据重复报告时只展示一次', () async {
      final harness = ModuleHarness();
      final module = harness.build();
      addTearDown(module.dispose);

      final receipt = _receipt();
      await module.report(receipt);
      await module.report(receipt);
      expect(harness.adapter.shownNotifications, hasLength(1));
    });

    test('被抑制的收据不会在失焦后重放', () async {
      final harness = ModuleHarness(activeConversationId: 'conv-1');
      final module = harness.build();
      addTearDown(module.dispose);

      // 前台查看同一会话：抑制，但收据标记为已处理。
      await module.report(_receipt(conversationId: 'conv-1'));
      expect(harness.adapter.shownNotifications, isEmpty);

      // 之后失焦，重复报告不得重放旧事件。
      harness.attention = AppAttentionState(
        lifecycleState: AppLifecycleState.resumed,
        windowFocused: false,
        location: Uri(path: '/chat'),
      );
      await module.report(_receipt(conversationId: 'conv-1'));
      expect(harness.adapter.shownNotifications, isEmpty);
    });

    test('保护超时后仍允许真正终态', () async {
      final harness = ModuleHarness();
      final module = harness.build();
      addTearDown(module.dispose);

      // 同一 generation：保护超时与真正终态是两个事件，分别展示。
      await module.report(
        _receipt(
          terminalKind: ChatGenerationTerminalKind.foregroundProtectionTimedOut,
          failureKind: ChatGenerationTerminalFailureKind.foregroundProtection,
        ),
      );
      await module.report(_receipt());
      expect(harness.adapter.shownNotifications, hasLength(2));
      expect(
        harness.adapter.shownNotifications[0].id,
        isNot(harness.adapter.shownNotifications[1].id),
      );
    });

    test('收据映射为固定安全文案与稳定 ID', () async {
      final harness = ModuleHarness();
      final module = harness.build();
      addTearDown(module.dispose);

      await module.report(_receipt());
      await module.report(
        _receipt(
          terminalKind: ChatGenerationTerminalKind.foregroundProtectionTimedOut,
          failureKind: ChatGenerationTerminalFailureKind.foregroundProtection,
        ),
      );
      await module.report(
        _receipt(
          generationId: 8,
          terminalKind: ChatGenerationTerminalKind.emptyReply,
          failureKind: ChatGenerationTerminalFailureKind.emptyReply,
        ),
      );
      await module.report(
        _receipt(
          generationId: 9,
          terminalKind: ChatGenerationTerminalKind.failed,
          failureKind: ChatGenerationTerminalFailureKind.network,
        ),
      );
      await module.report(
        _receipt(
          generationId: 10,
          terminalKind: ChatGenerationTerminalKind.failed,
          failureKind: ChatGenerationTerminalFailureKind.unknown,
        ),
      );
      await module.report(
        _receipt(
          generationId: 11,
          terminalKind: ChatGenerationTerminalKind.persistenceFailed,
          failureKind: ChatGenerationTerminalFailureKind.persistence,
        ),
      );
      final shown = harness.adapter.shownNotifications;

      // 预核对 FNV 向量（计划 5.2）。
      expect(shown[0].id, 1672833428);
      expect(shown[1].id, 937742124);
      expect(
        shown[0].payload,
        '{"v":1,"eventKey":"v1:$_session:7:succeeded","conversationId":"conv-1"}',
      );

      // 固定安全文案表（计划 3.4）。
      expect(shown[0].title, '生成完成');
      expect(shown[0].body, '正文 12 字 · 推理 3 字');
      expect(shown[0].publicTitle, '生成完成');
      expect(shown[0].publicBody, '请打开应用查看');

      expect(shown[1].title, '后台保护已结束');
      expect(shown[1].body, '请打开应用查看生成状态');
      expect(shown[1].publicTitle, '后台保护已结束');
      expect(shown[1].publicBody, '请打开应用查看生成状态');

      expect(shown[2].title, '生成未完成');
      expect(shown[2].body, '模型返回了空回复');
      expect(shown[2].publicTitle, '生成未完成');
      expect(shown[2].publicBody, '请打开应用查看');

      expect(shown[3].title, '生成失败');
      expect(shown[3].body, '网络不可达');

      expect(shown[4].title, '生成失败');
      expect(shown[4].body, '请打开应用查看详情');

      expect(shown[5].title, '结果保存失败');
      expect(shown[5].body, '回复结果未能保存，请打开应用查看');
      expect(shown[5].publicTitle, '结果保存失败');
      expect(shown[5].publicBody, '请打开应用查看');
    });
  });

  group('report fail-open 与初始化时序', () {
    test('平台初始化和展示失败均不向调用者抛出', () async {
      // 初始化失败：report 正常完成，不调用 show，记录固定诊断。
      var harness = ModuleHarness();
      harness.adapter.initializeError = StateError('initialize failed');
      var module = harness.build();
      await expectLater(module.report(_receipt()), completes);
      expect(harness.adapter.shownNotifications, isEmpty);
      expect(
        harness.diagnostics,
        contains('terminal_adapter_initialize_failed'),
      );
      await module.dispose();

      // 展示失败：report 正常完成，show 被调用一次，记录固定诊断。
      harness = ModuleHarness();
      harness.adapter.showError = StateError('show failed');
      module = harness.build();
      await expectLater(module.report(_receipt()), completes);
      expect(harness.adapter.shownNotifications, hasLength(1));
      expect(
        harness.diagnostics,
        contains('terminal_notification_show_failed'),
      );
      await module.dispose();
    });

    test('report 在初始化完成前到达时等待同一个 start future', () async {
      final harness = ModuleHarness();
      final module = harness.build();
      addTearDown(module.dispose);
      final gate = Completer<void>();
      harness.adapter.initializeGate = gate;

      // 两个 report 在初始化完成前先后到达。
      final first = module.report(_receipt());
      final second = module.report(_receipt());
      await pumpEventQueue();

      // 初始化尚未完成：show 不发生，且两条 report 共享同一个 start future。
      expect(harness.adapter.shownNotifications, isEmpty);
      expect(harness.adapter.initializeCallCount, 1);

      gate.complete();
      await first;
      await second;
      // 同一收据：等待初始化后只展示一次。
      expect(harness.adapter.shownNotifications, hasLength(1));
    });

    test('展示失败不完成 report 去重且后续重复报告可重试', () async {
      final harness = ModuleHarness();
      final module = harness.build();
      addTearDown(module.dispose);
      final receipt = _receipt();

      harness.adapter.showError = StateError('show failed');
      await module.report(receipt);
      expect(
        harness.diagnostics,
        contains('terminal_notification_show_failed'),
      );

      // 展示失败不完成去重：重复报告可以重试。
      harness.adapter.showError = null;
      await module.report(receipt);
      expect(harness.adapter.shownNotifications, hasLength(2));

      // 成功后进入 completed 集合：不再重放。
      await module.report(receipt);
      expect(harness.adapter.shownNotifications, hasLength(2));
    });
  });

  group('有界集合与 dispose', () {
    test('completed 去重集合和 in-flight 集合都有上限', () async {
      // completed 上限 512：第 513 个 key 逐出最旧 key，旧收据可重新报告。
      final harness = ModuleHarness();
      final module = harness.build();
      addTearDown(module.dispose);
      final first = _receipt(generationId: 1);
      await module.report(first);
      for (var generationId = 2; generationId <= 513; generationId += 1) {
        await module.report(_receipt(generationId: generationId));
      }
      expect(harness.adapter.shownNotifications, hasLength(513));
      await module.report(first); // 最旧 key 已逐出：重新展示。
      expect(harness.adapter.shownNotifications, hasLength(514));

      // in-flight 上限 32：满载时忽略新输入并记录固定诊断。
      final boundedHarness = ModuleHarness();
      final boundedModule = boundedHarness.build();
      addTearDown(boundedModule.dispose);
      final gate = Completer<void>();
      boundedHarness.adapter.showGate = gate;
      final pending = <Future<void>>[
        for (var generationId = 1; generationId <= 32; generationId += 1)
          boundedModule.report(_receipt(generationId: generationId)),
      ];
      await pumpEventQueue();
      expect(boundedHarness.adapter.shownNotifications, hasLength(32));

      await boundedModule.report(_receipt(generationId: 33)); // 满载被忽略。
      expect(
        boundedHarness.diagnostics,
        contains('notification_in_flight_limit'),
      );
      gate.complete();
      await Future.wait(pending);
    });

    test('dispose 幂等并取消激活订阅', () async {
      final harness = ModuleHarness();
      final module = harness.build();

      await module.start();
      expect(harness.adapter.activationsController.hasListener, isTrue);

      await module.dispose();
      await module.dispose(); // 幂等：adapter 只 dispose 一次。
      expect(harness.adapter.disposeCallCount, 1);
      expect(harness.adapter.activationsController.hasListener, isFalse);

      // dispose 后到达的激活不再消费。
      harness.adapter.emit(_activation());
      await pumpEventQueue();
      expect(harness.openChatCalls, isEmpty);
      await harness.adapter.activationsController.close();
    });
  });

  group('activation 导航（真实帧驱动）', () {
    testWidgets('hot 与 pending activation 只导航一次', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final harness = ModuleHarness();
      harness.existingConversations.add('conv-1');
      final activation = _activation();
      harness.adapter.pendingActivation = activation;
      final module = harness.build();
      addTearDown(() async {
        await module.dispose();
        await harness.adapter.activationsController.close();
      });

      // start 消费冷启动 pending 激活；同 eventKey 的 hot 激活被 in-flight
      // 拦截（hot 与 pending 只消费一次）。
      await module.start();
      harness.adapter.emit(activation);
      await untilInMicrotasks(() => tester.binding.hasScheduledFrame);
      await tester.pump();
      expect(harness.openChatCalls, ['conv-1']);

      // 导航完成后同一 eventKey 再次 hot 触发：被 completed 集合拦截。
      harness.adapter.emit(activation);
      await tester.pump();
      expect(harness.openChatCalls, ['conv-1']);
    });

    testWidgets('空闲 scheduler 会主动请求导航帧', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final harness = ModuleHarness();
      harness.existingConversations.add('conv-1');
      final module = harness.build();
      addTearDown(() async {
        await module.dispose();
        await harness.adapter.activationsController.close();
      });
      await module.start();
      expect(tester.binding.hasScheduledFrame, isFalse); // 起点：scheduler 空闲。

      harness.adapter.emit(_activation());
      // 只排空微任务、不 pump：restoreHost 完成后模块自己注册 post-frame
      // 并调用 ensureVisualUpdate 请求导航帧。
      await untilInMicrotasks(() => tester.binding.hasScheduledFrame);
      expect(tester.binding.hasScheduledFrame, isTrue);

      await tester.pump();
      expect(harness.openChatCalls, ['conv-1']);
    });

    testWidgets('导航排队后 dispose 不执行 openChat', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final harness = ModuleHarness();
      harness.existingConversations.add('conv-1');
      final module = harness.build();
      addTearDown(() async {
        await module.dispose();
        await harness.adapter.activationsController.close();
      });
      await module.start();

      harness.adapter.emit(_activation());
      // 等待导航已注册 post-frame（帧尚未执行）。
      await untilInMicrotasks(() => tester.binding.hasScheduledFrame);

      await module.dispose();
      await tester.pump(); // 排队的帧此时执行：回调必须跳过 openChat。
      expect(harness.openChatCalls, isEmpty);
    });

    testWidgets('窗口恢复或导航失败后再次点击可以重试', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final harness = ModuleHarness();
      harness.existingConversations.add('conv-1');
      final module = harness.build();
      addTearDown(() async {
        await module.dispose();
        await harness.adapter.activationsController.close();
      });
      await module.start();
      final activation = _activation();

      // 窗口恢复失败：不导航、不标记完成，只记固定诊断。
      harness.restoreHostShouldThrow = true;
      harness.adapter.emit(activation);
      await untilInMicrotasks(
        () => harness.diagnostics.contains('window_restore_or_focus_failed'),
      );
      expect(harness.openChatCalls, isEmpty);

      // 恢复成功后再次点击同一激活：可以重试。
      harness.restoreHostShouldThrow = false;
      harness.adapter.emit(activation);
      await untilInMicrotasks(() => tester.binding.hasScheduledFrame);
      await tester.pump();
      expect(harness.openChatCalls, ['conv-1']);

      // 导航失败（openChat 抛错）：不标记完成，只记固定诊断。
      harness.openChatShouldThrow = true;
      final failedActivation = _activation(
        eventKey: 'v1:$_session:8:succeeded',
      );
      harness.adapter.emit(failedActivation);
      await untilInMicrotasks(() => tester.binding.hasScheduledFrame);
      await tester.pump();
      await untilInMicrotasks(
        () => harness.diagnostics.contains('notification_navigation_failed'),
      );
      expect(harness.openChatCalls, hasLength(2));

      // 修复后再次点击：可以重试并成功。
      harness.openChatShouldThrow = false;
      harness.adapter.emit(failedActivation);
      await untilInMicrotasks(() => tester.binding.hasScheduledFrame);
      await tester.pump();
      expect(harness.openChatCalls, hasLength(3));

      // 成功后同一 eventKey 再次点击：不再重放。
      harness.adapter.emit(failedActivation);
      await tester.pump();
      expect(harness.openChatCalls, hasLength(3));
    });

    testWidgets('已删除会话回退聊天根页', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final harness = ModuleHarness();
      // existingConversations 为空：目标会话已删除。
      final module = harness.build();
      addTearDown(() async {
        await module.dispose();
        await harness.adapter.activationsController.close();
      });
      await module.start();

      harness.adapter.emit(_activation());
      await untilInMicrotasks(() => tester.binding.hasScheduledFrame);
      await tester.pump();
      expect(harness.openChatCalls, [null]);
    });

    testWidgets('会话存在判断在导航帧读取而不捕获启动期空列表', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final harness = ModuleHarness();
      final module = harness.build();
      addTearDown(() async {
        await module.dispose();
        await harness.adapter.activationsController.close();
      });
      await module.start();

      harness.adapter.emit(_activation());
      // 导航已排队但帧未执行：此刻会话列表仍为空（启动期状态）。
      await untilInMicrotasks(() => tester.binding.hasScheduledFrame);

      // 帧执行前会话出现：导航帧必须读取最新列表，不得捕获启动期空列表。
      harness.existingConversations.add('conv-1');
      await tester.pump();
      expect(harness.openChatCalls, ['conv-1']);
    });
  });
}

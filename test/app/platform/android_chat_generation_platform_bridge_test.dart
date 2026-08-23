import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/notifications/chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/app/platform/android_chat_generation_foreground_service.dart';
import 'package:oh_my_llm/app/platform/android_chat_generation_platform_bridge.dart';
import 'package:oh_my_llm/app/platform/android_chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/app/platform/android_system_notification_settings.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';
import 'package:oh_my_llm/features/settings/application/ports/system_notification_settings.dart';

/// 生产通道名：本任务暂用既有前台服务通道名，与尚未迁移的 Kotlin runtime 协作。
const _channelName = 'yuzu.shiki.oh_my_llm/chat_generation_foreground_service';

/// 固定测试 session 的合法 v1 payload（经共享严格 codec 编码）。
String _validPayload() {
  const codec = ChatGenerationNotificationPayloadCodec();
  return codec.encode(
    eventKey: 'v1:000102030405060708090a0b0c0d0e0f:7:succeeded',
    conversationId: 'conv-1',
  )!;
}

ChatGenerationForegroundPayload _foregroundPayload() =>
    const ChatGenerationForegroundPayload(
      token: 7,
      conversationId: 'conv-1',
      title: '正在生成',
      text: '正文 3 字 · 推理 2 字',
      publicTitle: '正在生成',
      publicText: '请打开应用查看进度',
      actionKind: ChatGenerationNotificationActionKind.stop,
      actionLabel: '停止生成',
    );

ChatGenerationSafeNotification _safeNotification(String payload) =>
    ChatGenerationSafeNotification(
      id: 1672833428,
      title: '生成完成',
      body: '正文 12 字 · 推理 34 字',
      publicTitle: '生成完成',
      publicBody: '请打开应用查看',
      payload: payload,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late MethodChannel channel;
  final calls = <MethodCall>[];

  /// 可按用例替换的「原生侧」响应器；返回 Future 表示永不完成（测超时）。
  Object? Function(MethodCall call)? responder;

  setUp(() {
    channel = MethodChannel(_channelName);
    calls.clear();
    responder = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return responder?.call(call);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  /// 通过默认 binary messenger 发送一次「原生 → Dart」回调，返回 handler
  /// 的应答（受理为 true / 拒绝为 false / 无 handler 为 null）。
  Future<Object?> sendNativeCallback(String method, Object? arguments) async {
    const codec = StandardMethodCodec();
    final message = codec.encodeMethodCall(MethodCall(method, arguments));
    final reply = await messenger.handlePlatformMessage(
      _channelName,
      message,
      null,
    );
    return reply == null ? null : codec.decodeEnvelope(reply);
  }

  group('平台回调分发', () {
    test('stop open timeout terminal activation 回调分发到对应窄流', () async {
      final bridge = AndroidChatGenerationPlatformBridge(channel: channel);
      addTearDown(bridge.dispose);

      final foregroundEvents = <ChatGenerationForegroundAction>[];
      final timeoutEvents = <ChatGenerationForegroundTimedOut>[];
      final terminalEvents = <ChatGenerationNotificationActivation>[];
      final foregroundSub = bridge.foregroundActions.listen(
        foregroundEvents.add,
      );
      final timeoutSub = bridge.timeoutActions.listen(timeoutEvents.add);
      final terminalSub = bridge.terminalActivations.listen(terminalEvents.add);
      addTearDown(foregroundSub.cancel);
      addTearDown(timeoutSub.cancel);
      addTearDown(terminalSub.cancel);

      expect(
        await sendNativeCallback('stopRequested', {
          'token': 7,
          'conversationId': 'conv-1',
        }),
        isTrue,
      );
      expect(
        await sendNativeCallback('openConversationRequested', {
          'conversationId': 'conv-2',
        }),
        isTrue,
      );
      expect(
        await sendNativeCallback('foregroundServiceTimedOut', {
          'token': 9,
          'conversationId': 'conv-3',
        }),
        isTrue,
      );
      expect(
        await sendNativeCallback('notificationActivated', _validPayload()),
        isTrue,
      );
      await pumpEventQueue();

      // 前台窄流只收 stop/open，不含 timeout；timeout 与终态激活各自独立成流。
      expect(foregroundEvents, hasLength(2));
      final stop = foregroundEvents[0] as ChatGenerationStopRequested;
      expect(stop.token, 7);
      expect(stop.conversationId, 'conv-1');
      final open =
          foregroundEvents[1] as ChatGenerationOpenConversationRequested;
      expect(open.conversationId, 'conv-2');

      expect(timeoutEvents, hasLength(1));
      expect(timeoutEvents.single.token, 9);
      expect(timeoutEvents.single.conversationId, 'conv-3');

      expect(terminalEvents, hasLength(1));
      expect(
        terminalEvents.single.eventKey,
        'v1:000102030405060708090a0b0c0d0e0f:7:succeeded',
      );
      expect(terminalEvents.single.conversationId, 'conv-1');
    });

    test('malformed 回调返回 false 且不进入任何窄流', () async {
      final bridge = AndroidChatGenerationPlatformBridge(channel: channel);
      addTearDown(bridge.dispose);
      final foregroundEvents = <ChatGenerationForegroundAction>[];
      final timeoutEvents = <ChatGenerationForegroundTimedOut>[];
      final terminalEvents = <ChatGenerationNotificationActivation>[];
      addTearDown(bridge.foregroundActions.listen(foregroundEvents.add).cancel);
      addTearDown(bridge.timeoutActions.listen(timeoutEvents.add).cancel);
      addTearDown(bridge.terminalActivations.listen(terminalEvents.add).cancel);

      final malformedCalls = <MethodCall>[
        // 参数不是 map。
        const MethodCall('stopRequested', 'not-a-map'),
        // stop 缺 token / token 非正 / token 非整数。
        const MethodCall('stopRequested', {'conversationId': 'conv-1'}),
        const MethodCall('stopRequested', {
          'token': 0,
          'conversationId': 'conv-1',
        }),
        const MethodCall('stopRequested', {
          'token': -1,
          'conversationId': 'conv-1',
        }),
        const MethodCall('stopRequested', {
          'token': 7.0,
          'conversationId': 'conv-1',
        }),
        // stop 会话 ID 空白 / 缺失。
        const MethodCall('stopRequested', {'token': 7, 'conversationId': '  '}),
        const MethodCall('stopRequested', {'token': 7}),
        // open 会话 ID 空白。
        const MethodCall('openConversationRequested', {'conversationId': '  '}),
        // timeout 缺字段。
        const MethodCall('foregroundServiceTimedOut', {'token': 7}),
        // 激活 payload 不是字符串 / 空串 / 非法 JSON。
        const MethodCall('notificationActivated', 123),
        const MethodCall('notificationActivated', ''),
        const MethodCall('notificationActivated', '{bad json'),
        // 激活 payload 含额外字段 / 未知版本。
        MethodCall(
          'notificationActivated',
          '{"v":1,"eventKey":"v1:000102030405060708090a0b0c0d0e0f:7:succeeded","conversationId":"conv-1","extra":true}',
        ),
        MethodCall(
          'notificationActivated',
          '{"v":2,"eventKey":"v1:000102030405060708090a0b0c0d0e0f:7:succeeded","conversationId":"conv-1"}',
        ),
        // 激活 payload 超 1024 UTF-8 bytes。
        MethodCall('notificationActivated', 'x' * 2000),
        // 未知方法。
        const MethodCall('bogusMethod', {
          'token': 7,
          'conversationId': 'conv-1',
        }),
      ];

      for (final call in malformedCalls) {
        final reply = await sendNativeCallback(call.method, call.arguments);
        expect(reply, isFalse, reason: '${call.method} 应被拒绝');
      }
      await pumpEventQueue();
      expect(foregroundEvents, isEmpty);
      expect(timeoutEvents, isEmpty);
      expect(terminalEvents, isEmpty);
    });

    test('timeout action stream 无 listener 时 ACK 为 false', () async {
      final bridge = AndroidChatGenerationPlatformBridge(channel: channel);
      addTearDown(bridge.dispose);

      // 无 listener：ACK false，事件不投递，Kotlin 收到后走原生 fallback。
      expect(
        await sendNativeCallback('foregroundServiceTimedOut', {
          'token': 9,
          'conversationId': 'conv-3',
        }),
        isFalse,
      );

      // 有 listener：ACK true 且事件送达。
      final events = <ChatGenerationForegroundTimedOut>[];
      final subscription = bridge.timeoutActions.listen(events.add);
      expect(
        await sendNativeCallback('foregroundServiceTimedOut', {
          'token': 9,
          'conversationId': 'conv-3',
        }),
        isTrue,
      );
      await pumpEventQueue();
      expect(events.single.token, 9);
      await subscription.cancel();
      await pumpEventQueue();

      // listener 全部取消后回到「无受理」状态。
      expect(
        await sendNativeCallback('foregroundServiceTimedOut', {
          'token': 9,
          'conversationId': 'conv-3',
        }),
        isFalse,
      );
    });
  });

  group('终态激活 pending', () {
    test('无 listener 的 warm 激活暂存后只取一次', () async {
      final bridge = AndroidChatGenerationPlatformBridge(channel: channel);
      addTearDown(bridge.dispose);

      // listener 尚未挂上：激活进入本地 pending 槽而不是被丢弃。
      expect(
        await sendNativeCallback('notificationActivated', _validPayload()),
        isTrue,
      );

      final first = await bridge.takePendingActivation();
      expect(first, isNotNull);
      expect(
        first!.eventKey,
        'v1:000102030405060708090a0b0c0d0e0f:7:succeeded',
      );
      expect(first.conversationId, 'conv-1');

      // 第二次取走时本地槽已空，转走 wire；mock 无 pending 返回 null。
      expect(await bridge.takePendingActivation(), isNull);
      expect(calls.map((call) => call.method).toSet(), {
        'takePendingNotificationActivation',
      });
    });

    test('冷启动 wire pending 激活解码成功且每次调用只读一次', () async {
      final bridge = AndroidChatGenerationPlatformBridge(channel: channel);
      addTearDown(bridge.dispose);
      responder = (call) {
        final wireCalls = calls
            .where(
              (entry) => entry.method == 'takePendingNotificationActivation',
            )
            .length;
        return wireCalls == 1 ? {'payload': _validPayload()} : null;
      };

      final first = await bridge.takePendingActivation();
      expect(first, isNotNull);
      expect(first!.conversationId, 'conv-1');

      // Kotlin 一次性 pending slot：第二次调用返回 null。
      expect(await bridge.takePendingActivation(), isNull);
    });

    test('wire pending 激活 malformed 一律 fail-open 为 null', () async {
      final bridge = AndroidChatGenerationPlatformBridge(channel: channel);
      addTearDown(bridge.dispose);

      final malformedResponses = <Object?>[
        {'payload': '{bad json'},
        {'payload': 123},
        {'other': 'value'},
        'bare-string',
        7,
      ];
      for (final response in malformedResponses) {
        responder = (call) => response;
        expect(
          await bridge.takePendingActivation(),
          isNull,
          reason: '$response 应被判为无 pending',
        );
      }
    });
  });

  group('命令结果解码', () {
    test('权限状态只接受已知枚举名', () async {
      final bridge = AndroidChatGenerationPlatformBridge(channel: channel);
      addTearDown(bridge.dispose);

      final knownStatuses = {
        'notRequired': ChatNotificationPermissionStatus.notRequired,
        'granted': ChatNotificationPermissionStatus.granted,
        'denied': ChatNotificationPermissionStatus.denied,
        'skippedAlreadyRequested':
            ChatNotificationPermissionStatus.skippedAlreadyRequested,
        'unavailable': ChatNotificationPermissionStatus.unavailable,
      };
      for (final entry in knownStatuses.entries) {
        responder = (_) => {'status': entry.key};
        expect(await bridge.ensureNotificationPermission(), entry.value);
      }
      for (final bad in [
        {'status': 'bogus'},
        'not-a-map',
        null,
      ]) {
        responder = (_) => bad;
        expect(
          await bridge.ensureNotificationPermission(),
          ChatNotificationPermissionStatus.unavailable,
          reason: '$bad 应退化为 unavailable',
        );
      }
    });

    test('命令结果只接受 accepted/failureCode 协议形状', () async {
      final bridge = AndroidChatGenerationPlatformBridge(channel: channel);
      addTearDown(bridge.dispose);

      responder = (_) => {'accepted': true};
      expect(
        await bridge.startForeground(_foregroundPayload()),
        const ChatForegroundCommandResult.accepted(),
      );

      for (final entry in {
        'startNotAllowed': ChatForegroundFailureCode.startNotAllowed,
        'staleToken': ChatForegroundFailureCode.staleToken,
      }.entries) {
        responder = (_) => {'accepted': false, 'failureCode': entry.key};
        expect(
          await bridge.removeForeground(token: 7, conversationId: 'conv-1'),
          ChatForegroundCommandResult.unavailable(entry.value),
        );
      }

      // 未知 failureCode、缺 failureCode、类型错误、非 map 都按协议不符处理。
      for (final bad in [
        {'accepted': false, 'failureCode': 'bogus'},
        {'accepted': false},
        {'accepted': 'yes'},
        'boom',
      ]) {
        responder = (_) => bad;
        expect(
          await bridge.startForeground(_foregroundPayload()),
          const ChatForegroundCommandResult.unavailable(
            ChatForegroundFailureCode.malformedPayload,
          ),
          reason: '$bad 应判为 malformedPayload',
        );
      }
    });

    test('待打开会话只接受非空白字符串', () async {
      final bridge = AndroidChatGenerationPlatformBridge(channel: channel);
      addTearDown(bridge.dispose);

      responder = (_) => 'conv-1';
      expect(await bridge.takePendingOpenConversation(), 'conv-1');
      for (final bad in [null, '   ', 123]) {
        responder = (_) => bad;
        expect(await bridge.takePendingOpenConversation(), isNull);
      }
    });

    test('设置状态只接受固定分类字符串', () async {
      final bridge = AndroidChatGenerationPlatformBridge(channel: channel);
      addTearDown(bridge.dispose);

      for (final entry in {
        'enabled': SystemNotificationStatus.enabled,
        'disabled': SystemNotificationStatus.disabled,
        'unavailable': SystemNotificationStatus.unavailable,
      }.entries) {
        responder = (_) => entry.key;
        expect(await bridge.getNotificationSettingsStatus(), entry.value);
      }
      for (final bad in ['bogus', 3, null]) {
        responder = (_) => bad;
        expect(
          await bridge.getNotificationSettingsStatus(),
          SystemNotificationStatus.unavailable,
          reason: '$bad 应退化为 unavailable',
        );
      }
    });
  });

  group('失败边界', () {
    test('channel timeout 和 PlatformException 均映射为 fail-open 结果', () async {
      // PlatformException：所有域统一降级，不抛原始异常。
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        throw PlatformException(code: 'platform-boom');
      });
      final bridge = AndroidChatGenerationPlatformBridge(channel: channel);
      addTearDown(bridge.dispose);

      expect(
        await bridge.ensureNotificationPermission(),
        ChatNotificationPermissionStatus.unavailable,
      );
      expect(
        await bridge.startForeground(_foregroundPayload()),
        const ChatForegroundCommandResult.unavailable(
          ChatForegroundFailureCode.nativeFailure,
        ),
      );
      expect(await bridge.takePendingOpenConversation(), isNull);
      expect(await bridge.takePendingActivation(), isNull);
      expect(
        await bridge.getNotificationSettingsStatus(),
        SystemNotificationStatus.unavailable,
      );
      expect(await bridge.openNotificationSettings(), isFalse);
      await expectLater(
        bridge.showTerminalNotification(_safeNotification(_validPayload())),
        throwsA(isA<AndroidTerminalNotificationShowException>()),
      );

      // 缺少原生 handler（MissingPluginException）映射为通道不可用。
      messenger.setMockMethodCallHandler(channel, null);
      final detachedBridge = AndroidChatGenerationPlatformBridge(
        channel: channel,
      );
      addTearDown(detachedBridge.dispose);
      expect(
        await detachedBridge.startForeground(_foregroundPayload()),
        const ChatForegroundCommandResult.unavailable(
          ChatForegroundFailureCode.channelUnavailable,
        ),
      );

      // 永不完成的 invoke 映射为 channelTimeout。
      messenger.setMockMethodCallHandler(
        channel,
        (call) => Completer<Object?>().future,
      );
      final slowBridge = AndroidChatGenerationPlatformBridge(
        channel: channel,
        commandTimeout: const Duration(milliseconds: 40),
      );
      addTearDown(slowBridge.dispose);
      expect(
        await slowBridge.startForeground(_foregroundPayload()),
        const ChatForegroundCommandResult.unavailable(
          ChatForegroundFailureCode.channelTimeout,
        ),
      );
      await expectLater(
        slowBridge.showTerminalNotification(_safeNotification(_validPayload())),
        throwsA(isA<AndroidTerminalNotificationShowException>()),
      );
    });

    test('原生拒绝展示终态通知时抛固定异常而非静默成功', () async {
      final bridge = AndroidChatGenerationPlatformBridge(channel: channel);
      addTearDown(bridge.dispose);
      responder = (_) => false;

      await expectLater(
        bridge.showTerminalNotification(_safeNotification(_validPayload())),
        throwsA(isA<AndroidTerminalNotificationShowException>()),
      );
    });
  });

  group('生命周期与共享', () {
    test('三个 Android 窄适配器共享一个 channel handler', () async {
      final bridge = AndroidChatGenerationPlatformBridge(channel: channel);
      addTearDown(bridge.dispose);
      final foreground = AndroidChatGenerationForegroundService(bridge: bridge);
      addTearDown(foreground.dispose);
      final terminal = AndroidChatGenerationTerminalNotificationAdapter(
        bridge: bridge,
      );
      addTearDown(terminal.dispose);
      final settings = AndroidSystemNotificationSettings(bridge: bridge);

      // 三个适配器的命令全部经同一个 channel 到达。
      responder = (_) => {'accepted': true};
      await foreground.ensureNotificationPermission();
      await foreground.start(_foregroundPayload());
      responder = (_) => true;
      await terminal.show(_safeNotification(_validPayload()));
      responder = (_) => 'enabled';
      expect(await settings.getStatus(), SystemNotificationStatus.enabled);
      responder = (_) => true;
      expect(await settings.openSettings(), isTrue);

      expect(calls.map((call) => call.method), [
        'ensureNotificationPermission',
        'startForegroundGeneration',
        'showTerminalNotification',
        'getNotificationSettingsStatus',
        'openNotificationSettings',
      ]);

      // 构造多个适配器没有替换或叠加 handler：回调仍由共享 bridge 分发，
      // 且各窄流只收到自己职责内的事件。
      final foregroundEvents = <ChatGenerationForegroundAction>[];
      final terminalEvents = <ChatGenerationNotificationActivation>[];
      addTearDown(foreground.actions.listen(foregroundEvents.add).cancel);
      addTearDown(terminal.activations.listen(terminalEvents.add).cancel);

      expect(
        await sendNativeCallback('openConversationRequested', {
          'conversationId': 'conv-2',
        }),
        isTrue,
      );
      expect(
        await sendNativeCallback('notificationActivated', _validPayload()),
        isTrue,
      );
      await pumpEventQueue();

      expect(foregroundEvents, hasLength(1));
      expect(
        foregroundEvents.single,
        isA<ChatGenerationOpenConversationRequested>(),
      );
      expect(terminalEvents, hasLength(1));
      expect(
        terminalEvents.single.eventKey,
        'v1:000102030405060708090a0b0c0d0e0f:7:succeeded',
      );
    });

    test('dispose 后 callback 不再分发且可重复 dispose', () async {
      final bridge = AndroidChatGenerationPlatformBridge(channel: channel);
      final foregroundEvents = <ChatGenerationForegroundAction>[];
      final timeoutEvents = <ChatGenerationForegroundTimedOut>[];
      final terminalEvents = <ChatGenerationNotificationActivation>[];
      final foregroundSub = bridge.foregroundActions.listen(
        foregroundEvents.add,
      );
      final timeoutSub = bridge.timeoutActions.listen(timeoutEvents.add);
      final terminalSub = bridge.terminalActivations.listen(terminalEvents.add);

      bridge.dispose();
      bridge.dispose(); // 幂等：第二次调用不再抛错。

      // handler 已移除：handlePlatformMessage 无响应返回 null。
      const codec = StandardMethodCodec();
      final message = codec.encodeMethodCall(
        const MethodCall('openConversationRequested', {
          'conversationId': 'conv-2',
        }),
      );
      final reply = await messenger.handlePlatformMessage(
        _channelName,
        message,
        null,
      );
      expect(reply, isNull);

      // 三条窄流都已关闭。
      await expectLater(bridge.foregroundActions, emitsDone);
      await expectLater(bridge.timeoutActions, emitsDone);
      await expectLater(bridge.terminalActivations, emitsDone);

      await foregroundSub.cancel();
      await timeoutSub.cancel();
      await terminalSub.cancel();
      await pumpEventQueue();
      expect(foregroundEvents, isEmpty);
      expect(timeoutEvents, isEmpty);
      expect(terminalEvents, isEmpty);
    });
  });
}

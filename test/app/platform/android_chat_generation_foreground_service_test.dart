import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/platform/android_chat_generation_foreground_service.dart';
import 'package:oh_my_llm/app/platform/android_chat_generation_platform_bridge.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';

/// 生产通道名：本任务暂用既有前台服务通道名，与尚未迁移的 Kotlin runtime 协作。
const _channelName = 'yuzu.shiki.oh_my_llm/chat_generation_foreground_service';

/// Dart 预编码的 foregroundProtectionTimedOut 激活 payload（共享严格 v1 codec
/// 产物）；前台 adapter 只透传、不解析。
const _timeoutActivationPayload =
    '{"v":1,"eventKey":"v1:000102030405060708090a0b0c0d0e0f:7:foregroundProtectionTimedOut","conversationId":"conv-1"}';

ChatGenerationForegroundPayload _payload({String? timeoutActivationPayload}) {
  return ChatGenerationForegroundPayload(
    token: 7,
    conversationId: 'conv-1',
    title: '正在生成',
    text: '正文 3 字 · 推理 2 字',
    publicTitle: '正在生成',
    publicText: '请打开应用查看进度',
    actionKind: ChatGenerationNotificationActionKind.stop,
    actionLabel: '停止生成',
    timeoutActivationPayload: timeoutActivationPayload,
  );
}

ChatGenerationForegroundPayload _noneActionPayload() {
  return const ChatGenerationForegroundPayload(
    token: 8,
    conversationId: 'conv-2',
    title: '正在停止',
    text: '正在停止并保存已有内容',
    publicTitle: '正在生成',
    publicText: '请打开应用查看进度',
    actionKind: ChatGenerationNotificationActionKind.none,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late MethodChannel channel;
  final calls = <MethodCall>[];
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

  /// 构造注入共享 bridge 的适配器；bridge 先注册 tearDown（LIFO 保证先释放
  /// adapter 再释放 bridge）。
  ({
    AndroidChatGenerationPlatformBridge bridge,
    AndroidChatGenerationForegroundService adapter,
  })
  createFixture() {
    final bridge = AndroidChatGenerationPlatformBridge(channel: channel);
    final adapter = AndroidChatGenerationForegroundService(bridge: bridge);
    addTearDown(bridge.dispose);
    addTearDown(adapter.dispose);
    return (bridge: bridge, adapter: adapter);
  }

  /// 通过默认 binary messenger 发送一次「原生 → Dart」回调，返回 handler 应答。
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

  group('输出编码', () {
    test('start/update/remove 编码为精确方法名与协议载荷', () async {
      responder = (_) => {'accepted': true};
      final fixture = createFixture();

      await fixture.adapter.start(_payload());
      await fixture.adapter.update(_payload());
      await fixture.adapter.remove(token: 7, conversationId: 'conv-1');

      expect(calls.map((call) => call.method), [
        'startForegroundGeneration',
        'updateForegroundGeneration',
        'removeForegroundGeneration',
      ]);

      const expectedPayload = {
        'token': 7,
        'conversationId': 'conv-1',
        'title': '正在生成',
        'text': '正文 3 字 · 推理 2 字',
        'publicTitle': '正在生成',
        'publicText': '请打开应用查看进度',
        'actionKind': 'stop',
        'actionLabel': '停止生成',
        'timeoutActivationPayload': null,
      };
      expect(calls[0].arguments, equals(expectedPayload));
      expect(calls[1].arguments, equals(expectedPayload));
      expect(
        calls[2].arguments,
        equals({'token': 7, 'conversationId': 'conv-1'}),
      );

      // token 保持 int 类型。
      expect((calls[0].arguments as Map)['token'], isA<int>());
      expect((calls[0].arguments as Map)['actionKind'], 'stop');
    });

    test('actionKind 为 none 时 actionLabel 以 null 参与编码', () async {
      responder = (_) => {'accepted': true};
      final fixture = createFixture();

      await fixture.adapter.update(_noneActionPayload());

      expect(calls, hasLength(1));
      expect(
        calls.single.arguments,
        equals({
          'token': 8,
          'conversationId': 'conv-2',
          'title': '正在停止',
          'text': '正在停止并保存已有内容',
          'publicTitle': '正在生成',
          'publicText': '请打开应用查看进度',
          'actionKind': 'none',
          'actionLabel': null,
          'timeoutActivationPayload': null,
        }),
      );
    });

    test(
      'foreground start update 原样传输 Dart 预编码 timeout activation payload',
      () async {
        responder = (_) => {'accepted': true};
        final fixture = createFixture();

        // 合法 v1 payload 原样出现在 start/update wire map。
        await fixture.adapter.start(
          _payload(timeoutActivationPayload: _timeoutActivationPayload),
        );
        await fixture.adapter.update(
          _payload(timeoutActivationPayload: _timeoutActivationPayload),
        );
        expect(
          (calls[0].arguments as Map)['timeoutActivationPayload'],
          _timeoutActivationPayload,
        );
        expect(
          (calls[1].arguments as Map)['timeoutActivationPayload'],
          _timeoutActivationPayload,
        );

        // Dart 侧只透传不解析：非 JSON 字符串也逐字节原样传输。
        await fixture.adapter.start(
          _payload(timeoutActivationPayload: 'not-a-json'),
        );
        expect(
          (calls[2].arguments as Map)['timeoutActivationPayload'],
          'not-a-json',
        );

        // 未设置时键恒存在、值为 null（与 actionLabel 恒键约定一致）。
        await fixture.adapter.start(_payload());
        expect(
          (calls[3].arguments as Map).containsKey('timeoutActivationPayload'),
          isTrue,
        );
        expect((calls[3].arguments as Map)['timeoutActivationPayload'], isNull);
      },
    );

    test('前台适配器只编码 ongoing 方法', () async {
      responder = (_) => {'accepted': true};
      final fixture = createFixture();

      await fixture.adapter.ensureNotificationPermission();
      await fixture.adapter.start(_payload());
      await fixture.adapter.update(_payload());
      await fixture.adapter.remove(token: 7, conversationId: 'conv-1');
      await fixture.adapter.takePendingOpenConversation();

      // 前台职责只覆盖 ongoing 协议；终态展示 / 终态激活 / 设置方法绝不出现。
      expect(calls.map((call) => call.method).toSet(), {
        'ensureNotificationPermission',
        'startForegroundGeneration',
        'updateForegroundGeneration',
        'removeForegroundGeneration',
        'takePendingOpenConversation',
      });
    });

    test('未注入 bridge 时自建 bridge 使用生产通道名并在 dispose 时一并释放', () async {
      responder = (_) => {'accepted': true};
      final adapter = AndroidChatGenerationForegroundService();
      addTearDown(adapter.dispose);

      final result = await adapter.start(_payload());

      // 调用到达本文件的生产通道名 mock，即证明自建 bridge 使用生产通道名。
      expect(result, const ChatForegroundCommandResult.accepted());
      expect(calls.single.method, 'startForegroundGeneration');

      // 自建 bridge 归属本 adapter：dispose 连带移除 channel handler。
      adapter.dispose();
      const codec = StandardMethodCodec();
      final message = codec.encodeMethodCall(
        const MethodCall('openConversationRequested', {
          'conversationId': 'conv-9',
        }),
      );
      final reply = await messenger.handlePlatformMessage(
        _channelName,
        message,
        null,
      );
      expect(reply, isNull);
    });
  });

  group('动作转发', () {
    test('stop open timeout 回调合并转发进 actions 窄流', () async {
      final fixture = createFixture();
      final events = <ChatGenerationForegroundAction>[];
      final subscription = fixture.adapter.actions.listen(events.add);
      addTearDown(subscription.cancel);

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
      await pumpEventQueue();

      expect(events, hasLength(3));
      final stop = events[0] as ChatGenerationStopRequested;
      expect(stop.token, 7);
      expect(stop.conversationId, 'conv-1');
      final open = events[1] as ChatGenerationOpenConversationRequested;
      expect(open.conversationId, 'conv-2');
      final timedOut = events[2] as ChatGenerationForegroundTimedOut;
      expect(timedOut.token, 9);
      expect(timedOut.conversationId, 'conv-3');
    });

    test(
      'actions 无 listener 时 timeout 回调 ACK false 监听后恢复且 stop open 不受影响',
      () async {
        final fixture = createFixture();

        // 尚无 listener：timeout 不被受理（Kotlin 收到 false 走原生 fallback）；
        // stop/open 沿用既有契约照常受理。
        expect(
          await sendNativeCallback('foregroundServiceTimedOut', {
            'token': 9,
            'conversationId': 'conv-3',
          }),
          isFalse,
        );
        expect(
          await sendNativeCallback('openConversationRequested', {
            'conversationId': 'conv-2',
          }),
          isTrue,
        );

        // actions 出现 listener：adapter 订阅桥接 timeout 流，ACK 恢复 true。
        final events = <ChatGenerationForegroundAction>[];
        final subscription = fixture.adapter.actions.listen(events.add);
        await pumpEventQueue();
        expect(
          await sendNativeCallback('foregroundServiceTimedOut', {
            'token': 9,
            'conversationId': 'conv-3',
          }),
          isTrue,
        );
        await pumpEventQueue();
        expect(events.single, isA<ChatGenerationForegroundTimedOut>());

        // listener 全部取消：回到无受理状态。
        await subscription.cancel();
        await pumpEventQueue();
        expect(
          await sendNativeCallback('foregroundServiceTimedOut', {
            'token': 9,
            'conversationId': 'conv-3',
          }),
          isFalse,
        );
      },
    );
  });

  group('dispose', () {
    test('dispose 移除动作订阅且可重复调用但不释放注入的共享 bridge', () async {
      final fixture = createFixture();
      final events = <ChatGenerationForegroundAction>[];
      final subscription = fixture.adapter.actions.listen(events.add);

      await sendNativeCallback('stopRequested', {
        'token': 7,
        'conversationId': 'conv-1',
      });
      await pumpEventQueue();
      expect(events, hasLength(1));

      fixture.adapter.dispose();
      fixture.adapter.dispose(); // 幂等：第二次调用不再抛错。

      // 动作流已关闭；共享 bridge 的 handler 仍然在位（端口各自 dispose
      // 不得重复释放 shared owner）。
      await expectLater(fixture.adapter.actions, emitsDone);
      expect(
        await sendNativeCallback('openConversationRequested', {
          'conversationId': 'conv-9',
        }),
        isTrue,
      );

      // 只有 bridge.dispose 才真正移除 handler。
      fixture.bridge.dispose();
      const codec = StandardMethodCodec();
      final message = codec.encodeMethodCall(
        const MethodCall('openConversationRequested', {
          'conversationId': 'conv-9',
        }),
      );
      final reply = await messenger.handlePlatformMessage(
        _channelName,
        message,
        null,
      );
      expect(reply, isNull);

      await subscription.cancel();
    });
  });
}

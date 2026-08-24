import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/notifications/chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/app/platform/android_chat_generation_platform_bridge.dart';
import 'package:oh_my_llm/app/platform/android_chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_notification_payload_codec.dart';

/// 生产通道名：与共享 bridge 默认构造一致。
const _channelName = 'yuzu.shiki.oh_my_llm/chat_generation_notifications';

/// 固定测试 session 的合法 v1 payload（经共享严格 codec 编码）。
String _validPayload() {
  const codec = ChatGenerationNotificationPayloadCodec();
  return codec.encode(
    eventKey: 'v1:000102030405060708090a0b0c0d0e0f:7:succeeded',
    conversationId: 'conv-1',
  )!;
}

ChatGenerationSafeNotification _notification() =>
    ChatGenerationSafeNotification(
      id: 1672833428,
      title: '生成完成',
      body: '正文 12 字 · 推理 34 字',
      publicTitle: '生成完成',
      publicBody: '请打开应用查看',
      payload: _validPayload(),
    );

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

  group('展示', () {
    test('终态适配器只发送安全通知字段', () async {
      final bridge = AndroidChatGenerationPlatformBridge(channel: channel);
      addTearDown(bridge.dispose);
      final adapter = AndroidChatGenerationTerminalNotificationAdapter(
        bridge: bridge,
      );
      addTearDown(adapter.dispose);
      responder = (_) => true;

      await adapter.show(_notification());

      expect(calls.single.method, 'showTerminalNotification');
      expect(calls.single.arguments, {
        'id': 1672833428,
        'title': '生成完成',
        'body': '正文 12 字 · 推理 34 字',
        'publicTitle': '生成完成',
        'publicBody': '请打开应用查看',
        'payload': _validPayload(),
      });
    });

    test('原生确认或拒绝展示都映射为固定结果', () async {
      // 原生返回 true：正常完成，不抛错。
      var bridge = AndroidChatGenerationPlatformBridge(channel: channel);
      addTearDown(bridge.dispose);
      var adapter = AndroidChatGenerationTerminalNotificationAdapter(
        bridge: bridge,
      );
      addTearDown(adapter.dispose);
      responder = (_) => true;
      await adapter.show(_notification());

      // 原生返回 false / 平台异常 / 超时 / 缺插件：统一固定异常，不泄漏原文。
      for (final failure in <void Function()>[
        () => responder = (_) => false,
        () => messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          throw PlatformException(code: 'boom');
        }),
      ]) {
        bridge = AndroidChatGenerationPlatformBridge(
          channel: channel,
          commandTimeout: const Duration(milliseconds: 40),
        );
        addTearDown(bridge.dispose);
        adapter = AndroidChatGenerationTerminalNotificationAdapter(
          bridge: bridge,
        );
        addTearDown(adapter.dispose);
        failure();
        await expectLater(
          adapter.show(_notification()),
          throwsA(isA<AndroidTerminalNotificationShowException>()),
        );
        // 恢复默认 mock，供下一轮循环重建边界。
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return responder?.call(call);
        });
      }

      // 永不完成的 invoke（超时）同样映射为固定异常。
      bridge = AndroidChatGenerationPlatformBridge(
        channel: channel,
        commandTimeout: const Duration(milliseconds: 40),
      );
      addTearDown(bridge.dispose);
      adapter = AndroidChatGenerationTerminalNotificationAdapter(
        bridge: bridge,
      );
      addTearDown(adapter.dispose);
      messenger.setMockMethodCallHandler(
        channel,
        (call) => Completer<Object?>().future,
      );
      await expectLater(
        adapter.show(_notification()),
        throwsA(isA<AndroidTerminalNotificationShowException>()),
      );

      // 无 handler（MissingPluginException）同样 fail-open 为固定异常。
      bridge = AndroidChatGenerationPlatformBridge(channel: channel);
      addTearDown(bridge.dispose);
      adapter = AndroidChatGenerationTerminalNotificationAdapter(
        bridge: bridge,
      );
      addTearDown(adapter.dispose);
      messenger.setMockMethodCallHandler(channel, null);
      await expectLater(
        adapter.show(_notification()),
        throwsA(isA<AndroidTerminalNotificationShowException>()),
      );
    });
  });

  group('激活', () {
    test('pending activation 只取一次', () async {
      final bridge = AndroidChatGenerationPlatformBridge(channel: channel);
      addTearDown(bridge.dispose);
      final adapter = AndroidChatGenerationTerminalNotificationAdapter(
        bridge: bridge,
      );
      addTearDown(adapter.dispose);

      // warm 回调先于任何 listener 到达：进入共享 bridge 的本地 pending 槽。
      expect(
        await sendNativeCallback('notificationActivated', _validPayload()),
        isTrue,
      );

      final first = await adapter.takePendingActivation();
      expect(first, isNotNull);
      expect(
        first!.eventKey,
        'v1:000102030405060708090a0b0c0d0e0f:7:succeeded',
      );
      expect(first.conversationId, 'conv-1');

      // 第二次取走时槽已空：转走 wire 且 mock 无 pending 返回 null。
      expect(await adapter.takePendingActivation(), isNull);
      final wireCallsBefore = calls
          .where((entry) => entry.method == 'takePendingNotificationActivation')
          .length;

      // 冷启动 wire pending：mock 对下一次 wire 调用返回激活 map，之后返回 null。
      responder = (call) {
        final wireCalls = calls
            .where(
              (entry) => entry.method == 'takePendingNotificationActivation',
            )
            .length;
        return wireCalls == wireCallsBefore + 1
            ? {'payload': _validPayload()}
            : null;
      };
      final cold = await adapter.takePendingActivation();
      expect(cold, isNotNull);
      expect(cold!.conversationId, 'conv-1');
      expect(await adapter.takePendingActivation(), isNull);
    });

    test('warm 激活经共享 bridge 流转发给 activations', () async {
      final bridge = AndroidChatGenerationPlatformBridge(channel: channel);
      addTearDown(bridge.dispose);
      final adapter = AndroidChatGenerationTerminalNotificationAdapter(
        bridge: bridge,
      );
      addTearDown(adapter.dispose);

      final events = <ChatGenerationNotificationActivation>[];
      final subscription = adapter.activations.listen(events.add);
      addTearDown(subscription.cancel);

      expect(
        await sendNativeCallback('notificationActivated', _validPayload()),
        isTrue,
      );
      await pumpEventQueue();

      expect(events, hasLength(1));
      expect(
        events.first.eventKey,
        'v1:000102030405060708090a0b0c0d0e0f:7:succeeded',
      );
      expect(events.first.conversationId, 'conv-1');
    });
  });

  group('生命周期', () {
    test('initialize 幂等完成且 dispose 不释放共享 bridge', () async {
      final bridge = AndroidChatGenerationPlatformBridge(channel: channel);
      addTearDown(bridge.dispose);
      final adapter = AndroidChatGenerationTerminalNotificationAdapter(
        bridge: bridge,
      );

      await adapter.initialize();
      await adapter.initialize(); // 幂等。

      await adapter.dispose();
      await adapter.dispose(); // 幂等。

      // 共享 bridge 仍安装着 handler：回调照常受理并进入激活流。
      final events = <ChatGenerationNotificationActivation>[];
      final subscription = bridge.terminalActivations.listen(events.add);
      addTearDown(subscription.cancel);
      expect(
        await sendNativeCallback('notificationActivated', _validPayload()),
        isTrue,
      );
      await pumpEventQueue();
      expect(events, hasLength(1));
    });
  });
}

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/platform/android_chat_generation_foreground_service.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';

/// 生产通道名，与适配器默认构造保持一致。
const _channelName = 'yuzu.shiki.oh_my_llm/chat_generation_foreground_service';

const _payload = ChatGenerationForegroundPayload(
  token: 7,
  conversationId: 'conv-1',
  title: '正在生成',
  text: '正文 3 字 · 推理 2 字',
  publicTitle: '正在生成',
  publicText: '请打开应用查看进度',
  actionKind: ChatGenerationNotificationActionKind.stop,
  actionLabel: '停止生成',
);

const _noneActionPayload = ChatGenerationForegroundPayload(
  token: 8,
  conversationId: 'conv-2',
  title: '正在停止',
  text: '正在停止并保存已有内容',
  publicTitle: '正在生成',
  publicText: '请打开应用查看进度',
  actionKind: ChatGenerationNotificationActionKind.none,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late MethodChannel channel;
  final calls = <MethodCall>[];
  Object? response;

  setUp(() {
    channel = MethodChannel(_channelName);
    calls.clear();
    response = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return response;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  /// 通过默认 binary messenger 发送一次「原生 → Dart」回调，返回解码后的
  /// handler 返回值（有效回调为 true，malformed 为 false）。
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
      response = {'accepted': true};
      final adapter = AndroidChatGenerationForegroundService(channel: channel);
      addTearDown(adapter.dispose);

      await expectLater(
        adapter.start(_payload),
        completion(const ChatForegroundCommandResult.accepted()),
      );
      await expectLater(
        adapter.update(_payload),
        completion(const ChatForegroundCommandResult.accepted()),
      );
      await expectLater(
        adapter.remove(token: 7, conversationId: 'conv-1'),
        completion(const ChatForegroundCommandResult.accepted()),
      );

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
      response = {'accepted': true};
      final adapter = AndroidChatGenerationForegroundService(channel: channel);
      addTearDown(adapter.dispose);

      await adapter.update(_noneActionPayload);

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
        }),
      );
    });

    test('未注入 channel 时使用生产通道名', () async {
      response = {'accepted': true};
      final adapter = AndroidChatGenerationForegroundService();
      addTearDown(adapter.dispose);

      final result = await adapter.start(_payload);

      expect(result, const ChatForegroundCommandResult.accepted());
      expect(calls.single.method, 'startForegroundGeneration');
    });
  });

  group('结果解码', () {
    test('ensureNotificationPermission 解码 status 映射', () async {
      final adapter = AndroidChatGenerationForegroundService(channel: channel);
      addTearDown(adapter.dispose);

      response = {'status': 'granted'};
      expect(
        await adapter.ensureNotificationPermission(),
        ChatNotificationPermissionStatus.granted,
      );
      response = {'status': 'denied'};
      expect(
        await adapter.ensureNotificationPermission(),
        ChatNotificationPermissionStatus.denied,
      );
      response = {'status': 'notRequired'};
      expect(
        await adapter.ensureNotificationPermission(),
        ChatNotificationPermissionStatus.notRequired,
      );
      response = {'status': 'skippedAlreadyRequested'};
      expect(
        await adapter.ensureNotificationPermission(),
        ChatNotificationPermissionStatus.skippedAlreadyRequested,
      );
      response = {'status': 'unavailable'};
      expect(
        await adapter.ensureNotificationPermission(),
        ChatNotificationPermissionStatus.unavailable,
      );
      // 未知 status、非 map、null 都落到 unavailable。
      response = {'status': 'bogus'};
      expect(
        await adapter.ensureNotificationPermission(),
        ChatNotificationPermissionStatus.unavailable,
      );
      response = 'not-a-map';
      expect(
        await adapter.ensureNotificationPermission(),
        ChatNotificationPermissionStatus.unavailable,
      );
      response = null;
      expect(
        await adapter.ensureNotificationPermission(),
        ChatNotificationPermissionStatus.unavailable,
      );

      expect(calls.map((call) => call.method).toSet(), {
        'ensureNotificationPermission',
      });
    });

    test('命令结果只接受 accepted/failureCode 协议形状', () async {
      final adapter = AndroidChatGenerationForegroundService(channel: channel);
      addTearDown(adapter.dispose);

      response = {'accepted': true};
      expect(
        await adapter.start(_payload),
        const ChatForegroundCommandResult.accepted(),
      );

      response = {'accepted': false, 'failureCode': 'startNotAllowed'};
      expect(
        await adapter.start(_payload),
        const ChatForegroundCommandResult.unavailable(
          ChatForegroundFailureCode.startNotAllowed,
        ),
      );

      response = {'accepted': false, 'failureCode': 'staleToken'};
      expect(
        await adapter.start(_payload),
        const ChatForegroundCommandResult.unavailable(
          ChatForegroundFailureCode.staleToken,
        ),
      );

      // 未知 failureCode、缺 failureCode、accepted 类型错误、非 map 都按
      // 协议不符处理，不抛异常。
      response = {'accepted': false, 'failureCode': 'bogus'};
      expect(
        await adapter.start(_payload),
        const ChatForegroundCommandResult.unavailable(
          ChatForegroundFailureCode.malformedPayload,
        ),
      );

      response = {'accepted': false};
      expect(
        await adapter.start(_payload),
        const ChatForegroundCommandResult.unavailable(
          ChatForegroundFailureCode.malformedPayload,
        ),
      );

      response = {'accepted': 'yes'};
      expect(
        await adapter.start(_payload),
        const ChatForegroundCommandResult.unavailable(
          ChatForegroundFailureCode.malformedPayload,
        ),
      );

      response = 'boom';
      expect(
        await adapter.start(_payload),
        const ChatForegroundCommandResult.unavailable(
          ChatForegroundFailureCode.malformedPayload,
        ),
      );
    });
  });

  group('原生回调解码', () {
    test('有效 stop/open/timeout 回调各 emit 一次 typed action 并返回 true', () async {
      final adapter = AndroidChatGenerationForegroundService(channel: channel);
      addTearDown(adapter.dispose);
      final events = <ChatGenerationForegroundAction>[];
      final subscription = adapter.actions.listen(events.add);
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

      // action 类型没有重写 ==，按类型与字段逐项断言（各恰好一次、顺序一致）。
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

    test('malformed 回调返回 false 且不发事件', () async {
      final adapter = AndroidChatGenerationForegroundService(channel: channel);
      addTearDown(adapter.dispose);
      final events = <ChatGenerationForegroundAction>[];
      final subscription = adapter.actions.listen(events.add);
      addTearDown(subscription.cancel);

      final malformedCalls = <MethodCall>[
        // stopRequested 缺 token。
        const MethodCall('stopRequested', {'conversationId': 'conv-1'}),
        // token 为 0。
        const MethodCall('stopRequested', {
          'token': 0,
          'conversationId': 'conv-1',
        }),
        // token 为负。
        const MethodCall('stopRequested', {
          'token': -1,
          'conversationId': 'conv-1',
        }),
        // token 为 double。
        const MethodCall('stopRequested', {
          'token': 7.0,
          'conversationId': 'conv-1',
        }),
        // 空白 conversation ID。
        const MethodCall('stopRequested', {
          'token': 7,
          'conversationId': '   ',
        }),
        // 缺 conversation ID。
        const MethodCall('stopRequested', {'token': 7}),
        // 未知方法。
        const MethodCall('bogusMethod', {
          'token': 7,
          'conversationId': 'conv-1',
        }),
        // 未知动作方法。
        const MethodCall('unknownAction', {
          'token': 7,
          'conversationId': 'conv-1',
        }),
        // 参数不是 map。
        const MethodCall('stopRequested', 'not-a-map'),
        // timeout 回调缺字段。
        const MethodCall('foregroundServiceTimedOut', {'token': 7}),
        // open 回调空白 ID。
        const MethodCall('openConversationRequested', {'conversationId': '  '}),
      ];

      for (final call in malformedCalls) {
        final reply = await sendNativeCallback(call.method, call.arguments);
        expect(reply, isFalse, reason: '${call.method} 应被拒绝');
      }
      expect(events, isEmpty);
    });
  });

  group('异常边界', () {
    test('PlatformException 映射为 nativeFailure，不抛给调用方', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'platform-boom');
      });
      final adapter = AndroidChatGenerationForegroundService(channel: channel);
      addTearDown(adapter.dispose);

      final result = await adapter.start(_payload);

      expect(
        result,
        const ChatForegroundCommandResult.unavailable(
          ChatForegroundFailureCode.nativeFailure,
        ),
      );
    });

    test('MissingPluginException 映射为 channelUnavailable', () async {
      // 不注册 mock：未 mock 的通道调用抛 MissingPluginException。
      messenger.setMockMethodCallHandler(channel, null);
      final adapter = AndroidChatGenerationForegroundService(channel: channel);
      addTearDown(adapter.dispose);

      final result = await adapter.start(_payload);

      expect(
        result,
        const ChatForegroundCommandResult.unavailable(
          ChatForegroundFailureCode.channelUnavailable,
        ),
      );
    });

    test('永不完成的 invoke 映射为 channelTimeout', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) => Completer<Object?>().future,
      );
      final adapter = AndroidChatGenerationForegroundService(
        channel: channel,
        commandTimeout: const Duration(milliseconds: 50),
      );
      addTearDown(adapter.dispose);

      final result = await adapter.start(_payload);

      expect(
        result,
        const ChatForegroundCommandResult.unavailable(
          ChatForegroundFailureCode.channelTimeout,
        ),
      );
    });

    test('权限与待打开会话在通道失败时也安全降级', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'boom');
      });
      final adapter = AndroidChatGenerationForegroundService(channel: channel);
      addTearDown(adapter.dispose);

      expect(
        await adapter.ensureNotificationPermission(),
        ChatNotificationPermissionStatus.unavailable,
      );
      expect(await adapter.takePendingOpenConversation(), isNull);
    });
  });

  group('待打开会话与 dispose', () {
    test('takePendingOpenConversation 接受非空白字符串，其余为 null', () async {
      final adapter = AndroidChatGenerationForegroundService(channel: channel);
      addTearDown(adapter.dispose);

      response = 'conv-1';
      expect(await adapter.takePendingOpenConversation(), 'conv-1');
      response = null;
      expect(await adapter.takePendingOpenConversation(), isNull);
      response = '   ';
      expect(await adapter.takePendingOpenConversation(), isNull);
      response = 123;
      expect(await adapter.takePendingOpenConversation(), isNull);

      expect(calls.map((call) => call.method).toSet(), {
        'takePendingOpenConversation',
      });
    });

    test('dispose 移除回调处理器并只关闭流一次', () async {
      final adapter = AndroidChatGenerationForegroundService(channel: channel);
      final events = <ChatGenerationForegroundAction>[];
      final subscription = adapter.actions.listen(events.add);

      await sendNativeCallback('stopRequested', {
        'token': 7,
        'conversationId': 'conv-1',
      });
      expect(events, hasLength(1));

      adapter.dispose();
      adapter.dispose(); // 幂等：第二次调用不再抛错。

      // 处理器已移除：handlePlatformMessage 无响应返回 null。
      const codec = StandardMethodCodec();
      final message = codec.encodeMethodCall(
        const MethodCall('stopRequested', {
          'token': 7,
          'conversationId': 'conv-1',
        }),
      );
      final reply = await messenger.handlePlatformMessage(
        _channelName,
        message,
        null,
      );
      expect(reply, isNull);

      // 流已关闭：emitsDone。
      await expectLater(adapter.actions, emitsDone);

      await subscription.cancel();
    });
  });
}

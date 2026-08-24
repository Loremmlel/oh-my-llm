import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/platform/windows_notification_host_client.dart';

/// 生产通道名：与 runner 通知宿主在同一原子提交内切换。
const _channelName = 'yuzu.shiki.oh_my_llm/windows_notifications';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late MethodChannel channel;
  final calls = <MethodCall>[];

  /// 可按用例替换的「原生侧」响应器；抛 PlatformException 或返回畸形应答
  /// 由各用例自行构造。
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

  /// 通过默认 binary messenger 发送一次「原生 → Dart」回调（live 推送路径）。
  Future<void> sendNativeActivation(String payload) async {
    const codec = StandardMethodCodec();
    final message = codec.encodeMethodCall(
      MethodCall('notificationActivated', payload),
    );
    await messenger.handlePlatformMessage(_channelName, message, null);
  }

  test('构造即安装唯一 handler，任何查询之前 live 回调不丢失', () async {
    // 构造完成、尚未执行任何 await/查询时，原生回调必须已能送达。
    final client = MethodChannelWindowsNotificationHostClient(channel: channel);
    addTearDown(client.dispose);

    final payloads = <String>[];
    final subscription = client.activationPayloads.listen(payloads.add);
    addTearDown(subscription.cancel);

    await sendNativeActivation('omll|before|query');
    expect(payloads, ['omll|before|query']);
    // 此前没有任何 Dart→native 查询被发出。
    expect(calls, isEmpty);

    responder = (_) => <Object?, Object?>{'available': true};
    expect(await client.getAvailable(), isTrue);
    // handler 仍是唯一一个：查询发出后 live 回调继续原样进入。
    await sendNativeActivation('omll|after|query');
    expect(payloads, ['omll|before|query', 'omll|after|query']);
  });

  test('takePendingActivationPayloads 一次取走完整 FIFO 列表并原子清空', () async {
    final client = MethodChannelWindowsNotificationHostClient(channel: channel);
    addTearDown(client.dispose);

    responder = (call) {
      if (call.method == 'takePendingNotificationActivations') {
        return <Object?>['omll|pending|1', 'omll|pending|2'];
      }
      return null;
    };
    expect(await client.takePendingActivationPayloads(), [
      'omll|pending|1',
      'omll|pending|2',
    ]);

    // 第二次取走为空：原生队列已被原子清空。
    responder = (_) => const <Object?>[];
    expect(await client.takePendingActivationPayloads(), isEmpty);
  });

  test('live callback 原样进入单一流，malformed 回调被丢弃', () async {
    final client = MethodChannelWindowsNotificationHostClient(channel: channel);
    addTearDown(client.dispose);

    final payloads = <String>[];
    final subscription = client.activationPayloads.listen(payloads.add);
    addTearDown(subscription.cancel);

    await sendNativeActivation('omll|live|1');
    await sendNativeActivation('omll|live|2');
    // 非字符串与空串不是合法 payload，不进入流。
    const codec = StandardMethodCodec();
    await messenger.handlePlatformMessage(
      _channelName,
      codec.encodeMethodCall(MethodCall('notificationActivated', 42)),
      null,
    );
    await messenger.handlePlatformMessage(
      _channelName,
      codec.encodeMethodCall(const MethodCall('notificationActivated', '')),
      null,
    );
    expect(payloads, ['omll|live|1', 'omll|live|2']);

    // dispose 后流关闭，同一 stream 不再接收。
    await client.dispose();
    await sendNativeActivation('omll|after|dispose');
    expect(payloads, ['omll|live|1', 'omll|live|2']);
  });

  test('malformed 应答与 PlatformException 固定映射为 unavailable 或 false', () async {
    final client = MethodChannelWindowsNotificationHostClient(channel: channel);
    addTearDown(client.dispose);

    // malformed 状态应答：非 map / available 非 bool。
    responder = (_) => 'available';
    expect(await client.getAvailable(), isFalse);
    responder = (_) => <Object?, Object?>{'available': 'yes'};
    expect(await client.getAvailable(), isFalse);

    // PlatformException 固定映射。
    responder = (_) => throw PlatformException(code: 'badArguments');
    expect(await client.getAvailable(), isFalse);
    expect(
      await client.show(id: 10001, title: 't', body: 'b', payload: 'p'),
      isFalse,
    );
    expect(await client.takePendingActivationPayloads(), isEmpty);

    // show 的非 bool 应答按 false 处理。
    responder = (_) => 'true';
    expect(
      await client.show(id: 10001, title: 't', body: 'b', payload: 'p'),
      isFalse,
    );

    // takePending 的列表内非字符串元素被过滤，字符串元素保持 FIFO。
    responder = (_) => <Object?>['ok', 7, 'omll|pending|tail'];
    expect(await client.takePendingActivationPayloads(), [
      'ok',
      'omll|pending|tail',
    ]);
  });

  test('dispose 幂等且不触发任何 native 调用', () async {
    final client = MethodChannelWindowsNotificationHostClient(channel: channel);
    final callsBeforeDispose = calls.length;

    await client.dispose();
    final callsAfterFirstDispose = calls.length;

    await client.dispose();
    expect(calls.length, callsAfterFirstDispose);
    // dispose 全程没有 Dart→native 调用：native host 生命周期归 runner。
    expect(callsAfterFirstDispose, callsBeforeDispose);

    // dispose 后所有查询走固定失败值，不再触达通道。
    expect(await client.getAvailable(), isFalse);
    expect(
      await client.show(id: 10001, title: 't', body: 'b', payload: 'p'),
      isFalse,
    );
    expect(await client.takePendingActivationPayloads(), isEmpty);
    expect(calls.length, callsBeforeDispose);
  });

  test('宿主命令超过固定超时后按不可用收束，不无限挂起', () async {
    // 永不完成的原生应答：模拟宿主卡死（COM stall / 死管道）。
    responder = (_) => Completer<Object?>().future;

    final client = MethodChannelWindowsNotificationHostClient(
      channel: channel,
      commandTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(client.dispose);

    expect(await client.getAvailable(), isFalse);
    expect(
      await client.show(id: 1, title: 't', body: 'b', payload: '{}'),
      isFalse,
    );
    expect(await client.takePendingActivationPayloads(), isEmpty);
  });
}

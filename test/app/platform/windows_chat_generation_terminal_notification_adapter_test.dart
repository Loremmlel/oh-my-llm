import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/notifications/chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/app/platform/windows_chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/app/platform/windows_notification_host_client.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_notification_payload_codec.dart';

/// 构造合法 eventKey：`v1:<32 位 hex>:<generation>:succeeded`。
String _eventKey(int generation) => 'v1:${'a' * 32}:$generation:succeeded';

/// 用共享严格 codec 编码合法 payload，保证测试输入与生产编码同源。
String _validPayload({
  required int generation,
  required String conversationId,
}) {
  return const ChatGenerationNotificationPayloadCodec().encode(
    eventKey: _eventKey(generation),
    conversationId: conversationId,
  )!;
}

const _notification = ChatGenerationSafeNotification(
  id: 10001,
  title: '生成完成',
  body: '正文 3 字 · 推理 0 字',
  publicTitle: '锁屏标题',
  publicBody: '锁屏正文',
  payload: '{"v":1,"eventKey":"k","conversationId":"c"}',
);

/// 共享宿主 client 的受控 Fake：记录调用并允许按用例注入应答与异常。
final class _FakeWindowsNotificationHostClient
    implements WindowsNotificationHostClient {
  _FakeWindowsNotificationHostClient({this.available = true});

  bool available;
  bool disposed = false;
  Object? availableError;
  int availableCalls = 0;

  final showRequests =
      <({int id, String title, String body, String payload})>[];
  bool showResult = true;
  Object? showError;

  List<String> pendingPayloads = const [];
  Object? pendingError;
  int pendingTakeCalls = 0;

  // 同步控制器：add 时同步完成解码入队，交付不依赖事件循环时序。
  final _livePayloads = StreamController<String>(sync: true);

  void emitLivePayload(String payload) => _livePayloads.add(payload);

  @override
  Stream<String> get activationPayloads => _livePayloads.stream;

  @override
  Future<bool> getAvailable() async {
    availableCalls += 1;
    if (availableError != null) throw availableError!;
    return available;
  }

  @override
  Future<bool> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    showRequests.add((id: id, title: title, body: body, payload: payload));
    if (showError != null) throw showError!;
    return showResult;
  }

  @override
  Future<List<String>> takePendingActivationPayloads() async {
    pendingTakeCalls += 1;
    if (pendingError != null) throw pendingError!;
    return pendingPayloads;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  test('安全 payload 和固定字段原样传给共享 Windows host client', () async {
    final client = _FakeWindowsNotificationHostClient();
    final adapter = WindowsChatGenerationTerminalNotificationAdapter(
      client: client,
    );
    addTearDown(adapter.dispose);

    await adapter.initialize();
    await adapter.show(_notification);

    final request = client.showRequests.single;
    expect(request.id, 10001);
    expect(request.title, '生成完成');
    expect(request.body, '正文 3 字 · 推理 0 字');
    expect(request.payload, _notification.payload);
    // public 副本只供 Android 锁屏使用，Windows 宿主协议没有对应字段。
  });

  test('host unavailable 时展示为 no-op', () async {
    final client = _FakeWindowsNotificationHostClient(available: false);
    final adapter = WindowsChatGenerationTerminalNotificationAdapter(
      client: client,
    );
    addTearDown(adapter.dispose);

    await adapter.initialize();

    // 展示不触达通道，但以固定异常暴露给深模块保留重试机会。
    await expectLater(
      adapter.show(_notification),
      throwsA(isA<WindowsTerminalNotificationShowException>()),
    );
    expect(client.showRequests, isEmpty);

    // 冷启动取走同样保持 no-op，不发无意义的通道查询。
    expect(await adapter.takePendingActivation(), isNull);
    expect(client.pendingTakeCalls, 0);
  });

  test('host show 返回 false 或异常时不泄漏原始异常', () async {
    final client = _FakeWindowsNotificationHostClient();
    final adapter = WindowsChatGenerationTerminalNotificationAdapter(
      client: client,
    );
    addTearDown(adapter.dispose);
    await adapter.initialize();

    client.showResult = false;
    await expectLater(
      adapter.show(_notification),
      throwsA(
        isA<WindowsTerminalNotificationShowException>().having(
          (exception) => exception.toString(),
          'toString',
          'WindowsTerminalNotificationShowException',
        ),
      ),
    );

    client.showError = PlatformException(code: 'boom', message: '原生细节');
    await expectLater(
      adapter.show(_notification),
      throwsA(isA<WindowsTerminalNotificationShowException>()),
    );
  });

  test('live 与 pending payload 使用同一严格 decoder', () async {
    final client = _FakeWindowsNotificationHostClient();
    final adapter = WindowsChatGenerationTerminalNotificationAdapter(
      client: client,
    );
    addTearDown(adapter.dispose);

    // 先建立激活流期望再触发投递；emitsDone 保证除该事件外无其他交付。
    final expectation = expectLater(
      adapter.activations,
      emitsInOrder([
        ChatGenerationNotificationActivation(
          eventKey: _eventKey(41),
          conversationId: 'conv-live',
        ),
        emitsDone,
      ]),
    );

    await adapter.initialize();

    // live 路径：原始 payload 经严格解码后才进入激活流。
    client.emitLivePayload(
      _validPayload(generation: 41, conversationId: 'conv-live'),
    );

    // pending 路径：同一 codec 解码出等值的激活对象作为返回值。
    client.pendingPayloads = [
      _validPayload(generation: 42, conversationId: 'conv-pending'),
    ];
    final pending = await adapter.takePendingActivation();
    expect(
      pending,
      ChatGenerationNotificationActivation(
        eventKey: _eventKey(42),
        conversationId: 'conv-pending',
      ),
    );

    // 关闭激活流并确认全程只有 live 这一次交付，pending 不重复进流。
    await adapter.dispose();
    await expectation;
  });

  test('pending 列表一次取走且多个合法 activation 按 FIFO 交付', () async {
    final client = _FakeWindowsNotificationHostClient();
    final adapter = WindowsChatGenerationTerminalNotificationAdapter(
      client: client,
    );
    addTearDown(adapter.dispose);

    // 除首个冷启动返回值外，其余合法项按列表顺序进入激活流。
    final expectation = expectLater(
      adapter.activations,
      emitsInOrder([
        ChatGenerationNotificationActivation(
          eventKey: _eventKey(12),
          conversationId: 'p2',
        ),
        ChatGenerationNotificationActivation(
          eventKey: _eventKey(13),
          conversationId: 'p3',
        ),
        emitsDone,
      ]),
    );

    client.pendingPayloads = [
      _validPayload(generation: 11, conversationId: 'p1'),
      _validPayload(generation: 12, conversationId: 'p2'),
      _validPayload(generation: 13, conversationId: 'p3'),
    ];
    await adapter.initialize();

    final first = await adapter.takePendingActivation();
    expect(first, isNotNull);
    expect(first!.conversationId, 'p1');
    // 原生列表一次取走，不做多次通道查询。
    expect(client.pendingTakeCalls, 1);

    await adapter.dispose();
    await expectation;
  });

  test('同一 pending payload 只取一次', () async {
    final client = _FakeWindowsNotificationHostClient();
    final adapter = WindowsChatGenerationTerminalNotificationAdapter(
      client: client,
    );
    addTearDown(adapter.dispose);

    // 全程期望激活流在关闭前零交付：payload 既不二次返回也不进流。
    final expectation = expectLater(adapter.activations, emitsDone);

    client.pendingPayloads = [
      _validPayload(generation: 21, conversationId: 'only'),
    ];
    await adapter.initialize();

    final first = await adapter.takePendingActivation();
    expect(first, isNotNull);

    // 原生队列原子清空后再次取走为空；同一 payload 不二次交付。
    client.pendingPayloads = const [];
    expect(await adapter.takePendingActivation(), isNull);
    expect(client.pendingTakeCalls, 2);

    await adapter.dispose();
    await expectation;
  });

  test('超长 未知版本 额外字段和 malformed payload 被忽略', () async {
    final client = _FakeWindowsNotificationHostClient();
    final adapter = WindowsChatGenerationTerminalNotificationAdapter(
      client: client,
    );
    addTearDown(adapter.dispose);

    // 两条路径的全部非法项都不产生交付，只有合法 payload 进入激活流。
    final expectation = expectLater(
      adapter.activations,
      emitsInOrder([
        ChatGenerationNotificationActivation(
          eventKey: _eventKey(34),
          conversationId: 'good',
        ),
        emitsDone,
      ]),
    );

    final oversized =
        '{"v":1,"eventKey":"${_eventKey(31)}","conversationId":"${'c' * 1200}"}';
    final unknownVersion =
        '{"v":2,"eventKey":"${_eventKey(32)}","conversationId":"ok"}';
    final extraField =
        '{"v":1,"eventKey":"${_eventKey(33)}","conversationId":"ok",'
        '"extra":true}';
    final brokenSyntax = '{"v":1,"eventKey":';

    // pending 路径：全部非法项被忽略，不产生冷启动激活。
    client.pendingPayloads = [
      oversized,
      unknownVersion,
      extraField,
      brokenSyntax,
    ];
    await adapter.initialize();
    expect(await adapter.takePendingActivation(), isNull);

    // live 路径：同样忽略非法项，只交付合法 payload。
    for (final payload in [
      oversized,
      unknownVersion,
      extraField,
      brokenSyntax,
    ]) {
      client.emitLivePayload(payload);
    }
    client.emitLivePayload(
      _validPayload(generation: 34, conversationId: 'good'),
    );

    await adapter.dispose();
    await expectation;
  });

  test('dispose 幂等且不释放共享 client', () async {
    final client = _FakeWindowsNotificationHostClient();
    final adapter = WindowsChatGenerationTerminalNotificationAdapter(
      client: client,
    );
    addTearDown(adapter.dispose);

    await adapter.initialize();
    await adapter.dispose();
    await adapter.dispose();

    // 共享 client 的生命周期归平台 composition，adapter 绝不代为释放。
    expect(client.disposed, isFalse);

    // dispose 后命令安全返回，不再触达通道。
    await adapter.show(_notification);
    expect(client.showRequests, isEmpty);
    expect(await adapter.takePendingActivation(), isNull);
    expect(client.pendingTakeCalls, 0);
  });

  test('initialize 幂等且宿主状态只查询一次', () async {
    final client = _FakeWindowsNotificationHostClient();
    final adapter = WindowsChatGenerationTerminalNotificationAdapter(
      client: client,
    );
    addTearDown(adapter.dispose);

    // 未重复订阅 client 流：同一条 live 回调只交付一次。
    final expectation = expectLater(
      adapter.activations,
      emitsInOrder([
        ChatGenerationNotificationActivation(
          eventKey: _eventKey(51),
          conversationId: 'once',
        ),
        emitsDone,
      ]),
    );

    await adapter.initialize();
    await adapter.initialize();
    expect(client.availableCalls, 1);

    client.emitLivePayload(
      _validPayload(generation: 51, conversationId: 'once'),
    );

    await adapter.dispose();
    await expectation;
  });
}

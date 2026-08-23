import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/platform/android_chat_generation_platform_bridge.dart';
import 'package:oh_my_llm/app/platform/android_system_notification_settings.dart';
import 'package:oh_my_llm/features/settings/application/ports/system_notification_settings.dart';

/// 生产通道名：与共享 bridge 默认构造一致。
const _channelName = 'yuzu.shiki.oh_my_llm/chat_generation_notifications';

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

  test('设置状态查询只委托共享 bridge 并映射固定分类', () async {
    final bridge = AndroidChatGenerationPlatformBridge(channel: channel);
    addTearDown(bridge.dispose);
    final adapter = AndroidSystemNotificationSettings(bridge: bridge);

    for (final entry in {
      'enabled': SystemNotificationStatus.enabled,
      'disabled': SystemNotificationStatus.disabled,
      'unavailable': SystemNotificationStatus.unavailable,
    }.entries) {
      responder = (_) => entry.key;
      expect(await adapter.getStatus(), entry.value);
    }

    // 未知值 / 非字符串 / 平台异常一律 fail-open 为 unavailable。
    for (final bad in <Object?>['bogus', 3, null]) {
      responder = (_) => bad;
      expect(
        await adapter.getStatus(),
        SystemNotificationStatus.unavailable,
        reason: '$bad 应退化为 unavailable',
      );
    }
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      throw PlatformException(code: 'boom');
    });
    expect(await adapter.getStatus(), SystemNotificationStatus.unavailable);

    // 只委托 getNotificationSettingsStatus，不发送任何其他方法。
    expect(calls.map((call) => call.method).toSet(), {
      'getNotificationSettingsStatus',
    });
  });

  test('打开系统通知设置只委托共享 bridge 并透传结果', () async {
    final bridge = AndroidChatGenerationPlatformBridge(channel: channel);
    addTearDown(bridge.dispose);
    final adapter = AndroidSystemNotificationSettings(bridge: bridge);

    responder = (_) => true;
    expect(await adapter.openSettings(), isTrue);

    responder = (_) => false;
    expect(await adapter.openSettings(), isFalse);

    // 平台异常 / 缺插件 / 超时都 fail-open 为 false，不抛错。
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      throw PlatformException(code: 'boom');
    });
    expect(await adapter.openSettings(), isFalse);

    messenger.setMockMethodCallHandler(channel, null);
    expect(await adapter.openSettings(), isFalse);

    var slowBridge = AndroidChatGenerationPlatformBridge(
      channel: channel,
      commandTimeout: const Duration(milliseconds: 40),
    );
    addTearDown(slowBridge.dispose);
    var slowAdapter = AndroidSystemNotificationSettings(bridge: slowBridge);
    messenger.setMockMethodCallHandler(
      channel,
      (call) => Completer<Object?>().future,
    );
    expect(await slowAdapter.openSettings(), isFalse);

    // 只委托 openNotificationSettings，无参数。
    expect(calls.map((call) => call.method).toSet(), {
      'openNotificationSettings',
    });
  });
}

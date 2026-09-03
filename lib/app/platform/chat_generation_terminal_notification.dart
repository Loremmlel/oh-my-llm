import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';

/// 展示一次聊天生成终态系统通知。
typedef ChatGenerationTerminalNotificationSender = Future<void> Function(
  ChatGenerationForegroundPayload payload,
);

/// 测试与非生产组合默认不触碰系统通知；生产由 bootstrap 覆盖。
final chatGenerationTerminalNotificationSenderProvider =
    Provider<ChatGenerationTerminalNotificationSender>(
      (ref) => _ignoreTerminalNotification,
    );

const _initializationSettings = InitializationSettings(
  android: AndroidInitializationSettings('ic_chat_generation'),
  windows: WindowsInitializationSettings(
    appName: 'Oh My LLM',
    appUserModelId: 'YuzuShiki.OhMyLlm',
    guid: '7e4b2c91-5d4a-4a8e-9f1b-2c6d3a80e751',
  ),
);

const _notificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'chat_generation_result',
    '聊天生成结果',
    channelDescription: '聊天回复生成完成或失败时的提醒',
    importance: Importance.high,
    priority: Priority.high,
  ),
  windows: WindowsNotificationDetails(),
);

/// 创建惰性系统通知 sender；生成未到终态时不初始化原生插件。
ChatGenerationTerminalNotificationSender
createChatGenerationTerminalNotificationSender({
  required TargetPlatform platform,
}) {
  if (platform != TargetPlatform.android &&
      platform != TargetPlatform.windows) {
    return _ignoreTerminalNotification;
  }

  final plugin = FlutterLocalNotificationsPlugin();
  Future<bool?>? initialization;
  return (payload) async {
    final initialized = await (initialization ??= plugin.initialize(
      settings: _initializationSettings,
    ));
    if (initialized != true) return;
    // 固定 ID 足够：应用同时只允许一个 generation，后一次结果覆盖前一次。
    await plugin.show(
      id: 4200,
      title: payload.title,
      body: payload.text,
      notificationDetails: _notificationDetails,
    );
  };
}

Future<void> _ignoreTerminalNotification(
  ChatGenerationForegroundPayload payload,
) async {}

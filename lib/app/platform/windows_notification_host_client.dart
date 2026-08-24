import 'dart:async';

import 'package:flutter/services.dart';

import 'package:oh_my_llm/app/platform/chat_generation_platform_command_timeout.dart';

/// Windows 通知宿主共享 MethodChannel 名。
///
/// 与 runner `windows_notification_host.cpp` 在同一原子提交内切换；宿主与
/// Dart 之间不存在第二条通道。
const windowsNotificationHostChannelName =
    'yuzu.shiki.oh_my_llm/windows_notifications';

/// Windows 通知宿主客户端契约。
///
/// 只暴露 runner 通知宿主的外部行为；`activationPayloads` 是原始 payload
/// 字符串流（安全性由共享严格 decoder 在 adapter 层判定），`getAvailable`
/// 只表达「runner host 可用」，不承诺系统开关开启或未来每次展示成功。
abstract interface class WindowsNotificationHostClient {
  /// 原生 `notificationActivated` 推送的原样 payload 流。
  Stream<String> get activationPayloads;

  /// 宿主是否可用；不可用时调用方应保持 no-op。
  Future<bool> getAvailable();

  /// 展示一条一次性 Toast；native 参数校验拒绝或通道失败返回 false。
  Future<bool> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  });

  /// 一次取走冷启动 pending 的完整 FIFO payload 列表并原子清空。
  Future<List<String>> takePendingActivationPayloads();

  /// 移除 Dart handler 并关闭流；幂等，不触发任何 native 调用。
  ///
  /// native host 的生命周期始终归 runner 进程所有，dispose 不调用 native
  /// shutdown——窗口仍在运行时通知宿主必须继续存活。
  Future<void> dispose();
}

/// 生产实现：包装唯一 MethodChannel。
///
/// 构造函数同步安装唯一 Dart handler，之后才允许任何 `await`——live 回调
/// 在构造与首次查询之间到达也不丢失。所有 malformed 应答与平台异常都收敛
/// 为固定值（false / 空列表），不向调用方泄漏异常原文。
final class MethodChannelWindowsNotificationHostClient
    implements WindowsNotificationHostClient {
  MethodChannelWindowsNotificationHostClient({
    MethodChannel? channel,
    Duration commandTimeout = chatGenerationPlatformCommandTimeout,
  }) : _channel =
           channel ?? const MethodChannel(windowsNotificationHostChannelName),
       _commandTimeout = commandTimeout {
    _channel.setMethodCallHandler(_handleNativeMethod);
  }

  final MethodChannel _channel;
  final Duration _commandTimeout;
  final _activations = StreamController<String>.broadcast();
  bool _disposed = false;

  @override
  Stream<String> get activationPayloads => _activations.stream;

  @override
  Future<bool> getAvailable() async {
    if (_disposed) return false;
    try {
      final value = await _channel
          .invokeMethod<Object?>('getNotificationHostStatus')
          .timeout(_commandTimeout);
      return _decodeAvailable(value);
    } on Exception {
      // MissingPluginException / PlatformException / TimeoutException / 通道
      // 失败统一映射为不可用；不区分失败原因，避免向调用方暴露异常细节。
      return false;
    }
  }

  @override
  Future<bool> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    if (_disposed) return false;
    try {
      final value = await _channel
          .invokeMethod<Object?>('showTerminalNotification', {
            'id': id,
            'title': title,
            'body': body,
            'payload': payload,
          })
          .timeout(_commandTimeout);
      return value is bool && value;
    } on Exception {
      return false;
    }
  }

  @override
  Future<List<String>> takePendingActivationPayloads() async {
    if (_disposed) return const [];
    try {
      final value = await _channel
          .invokeMethod<Object?>('takePendingNotificationActivations')
          .timeout(_commandTimeout);
      if (value is! List) return const [];
      // 逐项严格过滤：任何非字符串元素都按 malformed 处理，整表保持 FIFO。
      return [
        for (final entry in value)
          if (entry is String) entry,
      ];
    } on Exception {
      return const [];
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    await _activations.close();
  }

  /// 只接受 `available` 为严格 bool 的 map 应答；其他形态按不可用处理。
  bool _decodeAvailable(Object? value) {
    if (value is! Map) return false;
    final available = value['available'];
    return available is bool && available;
  }

  Future<dynamic> _handleNativeMethod(MethodCall call) async {
    if (_disposed) return null;
    if (call.method == 'notificationActivated') {
      // 回调参数是原始 payload 字符串本身；空串/非字符串按 malformed 丢弃。
      final arguments = call.arguments;
      if (arguments is String && arguments.isNotEmpty) {
        _activations.add(arguments);
      }
    }
    return null;
  }
}

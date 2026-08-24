import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/platform/windows_notification_host_client.dart';
import 'package:oh_my_llm/app/platform/windows_system_notification_settings.dart';
import 'package:oh_my_llm/features/settings/application/ports/system_notification_settings.dart';

/// 共享宿主 client 的受控 Fake：只服务状态探测，不创建任何通道。
final class _FakeWindowsNotificationHostClient
    implements WindowsNotificationHostClient {
  bool available = true;
  Object? availableError;
  int availableCalls = 0;

  @override
  Future<bool> getAvailable() async {
    availableCalls += 1;
    if (availableError != null) throw availableError!;
    return available;
  }

  @override
  Stream<String> get activationPayloads => throw UnimplementedError();

  @override
  Future<bool> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) => throw UnimplementedError();

  @override
  Future<List<String>> takePendingActivationPayloads() =>
      throw UnimplementedError();

  @override
  Future<void> dispose() async {}
}

/// 进程启动 seam 的记录 Fake：记录 executable/arguments/mode，不启动 explorer。
final class _RecordingLauncher implements WindowsProcessLauncher {
  final launches =
      <({String executable, List<String> arguments, ProcessStartMode mode})>[];
  Object? error;

  @override
  Future<void> start({
    required String executable,
    required List<String> arguments,
    required ProcessStartMode mode,
  }) async {
    launches.add((
      executable: executable,
      arguments: List.of(arguments),
      mode: mode,
    ));
    if (error != null) throw error!;
  }
}

void main() {
  test('Windows 设置状态只反映共享 host 可用性', () async {
    final client = _FakeWindowsNotificationHostClient();
    final settings = WindowsSystemNotificationSettings(client: client);

    client.available = true;
    expect(await settings.getStatus(), SystemNotificationStatus.available);

    client.available = false;
    expect(await settings.getStatus(), SystemNotificationStatus.unavailable);

    // 宿主查询异常同样退化为 unavailable，不向调用方抛出。
    client.availableError = PlatformException(code: 'boom');
    expect(await settings.getStatus(), SystemNotificationStatus.unavailable);

    // 每次状态查询恰好一次宿主探测，不读取任何系统级开关。
    expect(client.availableCalls, 3);
  });

  test('Windows 设置通过 launcher seam 只用 explorer 参数数组且异常返回 false', () async {
    final client = _FakeWindowsNotificationHostClient();
    final launcher = _RecordingLauncher();
    final settings = WindowsSystemNotificationSettings(
      client: client,
      launcher: launcher,
    );

    expect(await settings.openSettings(), isTrue);
    final launch = launcher.launches.single;
    expect(launch.executable, 'explorer.exe');
    expect(launch.arguments, ['ms-settings:notifications']);
    // 分离模式：设置页生命周期与应用进程解耦。
    expect(launch.mode, ProcessStartMode.detached);

    // 启动失败 fail-open 为 false，不抛出、不重试。
    launcher.error = Exception('explorer 不存在');
    expect(await settings.openSettings(), isFalse);
    expect(launcher.launches, hasLength(2));
  });
}

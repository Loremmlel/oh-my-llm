import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/application/ports/system_notification_settings.dart';
import 'package:oh_my_llm/features/settings/application/system_notifications/system_notification_status_controller.dart';

// ── 测试 Fake ───────────────────────────────────────────────

/// 可控的系统通知设置端口：记录调用次数，允许用例改写应答、注入异常
/// 或用 Completer 挂起查询以构造稳定的 loading 窗口。
class _FakeSystemNotificationSettings implements SystemNotificationSettings {
  SystemNotificationStatus status = SystemNotificationStatus.enabled;
  bool openSettingsResult = true;
  bool throwOnGetStatus = false;
  Completer<void>? statusGate;

  int getStatusCallCount = 0;
  int openSettingsCallCount = 0;

  @override
  Future<SystemNotificationStatus> getStatus() async {
    getStatusCallCount += 1;
    final gate = statusGate;
    if (gate != null) {
      await gate.future;
    }
    if (throwOnGetStatus) {
      throw StateError('平台状态查询失败');
    }
    return status;
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCallCount += 1;
    return openSettingsResult;
  }
}

ProviderContainer _containerWith(SystemNotificationSettings settings) {
  return ProviderContainer(
    overrides: [systemNotificationSettingsProvider.overrideWithValue(settings)],
  );
}

void main() {
  group('SystemNotificationStatusController', () {
    test('状态查询异常时映射为不可用', () async {
      final fake = _FakeSystemNotificationSettings()..throwOnGetStatus = true;
      final container = _containerWith(fake);
      addTearDown(container.dispose);

      final status = await container.read(
        systemNotificationStatusProvider.future,
      );

      expect(status, SystemNotificationStatus.unavailable);
    });

    test('刷新时重新查询平台状态', () async {
      final fake = _FakeSystemNotificationSettings();
      final container = _containerWith(fake);
      addTearDown(container.dispose);

      expect(
        await container.read(systemNotificationStatusProvider.future),
        SystemNotificationStatus.enabled,
      );
      expect(fake.getStatusCallCount, 1);

      // 挂起下一次查询：refresh 把状态置回 loading 保持可观察，
      // 完成后携带新值落地，且确实重新调用了端口。
      final gate = Completer<void>();
      fake
        ..statusGate = gate
        ..status = SystemNotificationStatus.disabled;

      final refreshFuture = container
          .read(systemNotificationStatusProvider.notifier)
          .refresh();
      expect(
        container.read(systemNotificationStatusProvider).isLoading,
        isTrue,
      );

      gate.complete();
      await refreshFuture;

      expect(fake.getStatusCallCount, 2);
      expect(
        container.read(systemNotificationStatusProvider).value,
        SystemNotificationStatus.disabled,
      );
    });

    test('打开设置返回平台端口结果', () async {
      for (final portResult in const [true, false]) {
        final fake = _FakeSystemNotificationSettings()
          ..openSettingsResult = portResult;
        final container = _containerWith(fake);
        addTearDown(container.dispose);

        final opened = await container
            .read(systemNotificationStatusProvider.notifier)
            .openSettings();

        expect(opened, portResult);
        expect(fake.openSettingsCallCount, 1);
      }
    });
  });
}

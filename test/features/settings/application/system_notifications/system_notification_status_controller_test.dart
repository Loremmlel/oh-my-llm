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

  /// 只拦截第一次查询（build）的 gate；用于构造 build 慢、refresh 快的乱序。
  Completer<void>? firstCallGate;

  int getStatusCallCount = 0;
  int openSettingsCallCount = 0;

  @override
  Future<SystemNotificationStatus> getStatus() async {
    getStatusCallCount += 1;
    // 慢查询返回发起时刻的应答：挂起期间改写 status 不影响本次查询结果，
    // 才能构造「build 拿到旧值、refresh 拿到新值」的查询乱序。
    final captured = status;
    final gate = statusGate;
    if (gate != null) {
      await gate.future;
      statusGate = null; // 只拦下一次查询（既有语义不变）。
    }
    final firstGate = firstCallGate;
    if (firstGate != null && getStatusCallCount == 1) {
      await firstGate.future;
    }
    if (throwOnGetStatus) {
      throw StateError('平台状态查询失败');
    }
    return captured;
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

    test('build 慢查询期间 refresh 完成后，build 的旧结果不得覆盖新值', () async {
      final fake = _FakeSystemNotificationSettings();
      final container = _containerWith(fake);
      addTearDown(container.dispose);

      final buildGate = Completer<void>();
      fake.firstCallGate = buildGate;
      fake.status = SystemNotificationStatus.enabled;
      // 触发 build：首次查询被 firstCallGate 挂起，构建「build 慢、refresh 快」。
      container.read(systemNotificationStatusProvider);

      // refresh 触发新查询并先完成（携带新值 disabled）。
      fake.status = SystemNotificationStatus.disabled;
      await container.read(systemNotificationStatusProvider.notifier).refresh();
      expect(
        container.read(systemNotificationStatusProvider).value,
        SystemNotificationStatus.disabled,
      );

      // build 的旧查询随后完成：等框架把 build 结果写回 state 的微任务链
      // （getStatus 恢复 → _queryStatus 恢复 → build 返回 → handleFuture .then
      // 写回）排空后再断言。写回链实为 4 跳，8 轮 = 2 倍余量；修复后该写回
      // 是「同值覆盖」，无可观察事件可当完成信号，只能让出微任务。await null
      // 不消耗真实时间；Riverpod 升级若改变写回跳数，需重核轮数是否仍足量。
      buildGate.complete();
      for (var i = 0; i < 8; i++) {
        await null;
      }
      expect(
        container.read(systemNotificationStatusProvider).value,
        SystemNotificationStatus.disabled,
      );
      expect(fake.getStatusCallCount, 2);
    });
  });
}

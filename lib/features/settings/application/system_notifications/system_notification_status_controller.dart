import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ports/system_notification_settings.dart';

/// 系统通知状态控制器：查询平台事实并提供打开系统设置的入口。
///
/// 只投影端口结果、不持有任何应用内偏好；平台查询异常统一映射为
/// unavailable，让 UI 在查询失败时也能渲染确定的状态而不是错误分支。
class SystemNotificationStatusController
    extends AsyncNotifier<SystemNotificationStatus> {
  @override
  Future<SystemNotificationStatus> build() => _queryStatus();

  /// 重新查询平台状态；查询期间把状态置回 loading，UI 可观察。
  Future<void> refresh() async {
    state = const AsyncLoading<SystemNotificationStatus>();
    final status = await _queryStatus();
    if (ref.mounted) {
      state = AsyncData(status);
    }
  }

  /// 请求打开系统通知设置页；原样返回端口结果，失败提示由 UI 层决定。
  Future<bool> openSettings() {
    return ref.read(systemNotificationSettingsProvider).openSettings();
  }

  Future<SystemNotificationStatus> _queryStatus() async {
    try {
      return await ref.read(systemNotificationSettingsProvider).getStatus();
    } catch (_) {
      return SystemNotificationStatus.unavailable;
    }
  }
}

/// 手写声明（无代码生成）：绑定控制器与状态类型。
final systemNotificationStatusProvider =
    AsyncNotifierProvider<
      SystemNotificationStatusController,
      SystemNotificationStatus
    >(SystemNotificationStatusController.new);

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 系统通知状态的固定分类。
enum SystemNotificationStatus {
  /// Android：系统通知已开启。
  enabled,

  /// Android：系统通知已被关闭。
  disabled,

  /// Windows：功能可用（未打包 API 无法可靠查询最终开关，不伪装成已开启）。
  available,

  /// 当前平台无法使用系统通知。
  unavailable,
}

/// 系统通知设置端口：状态查询与打开系统设置入口。
///
/// 只报告平台事实，不解释生成结果，也没有应用内开关；实现由 app
/// composition 绑定（Android/Windows adapter 或 no-op）。
abstract interface class SystemNotificationSettings {
  /// 查询当前系统通知状态；实现不得抛出（异常由 controller 映射）。
  Future<SystemNotificationStatus> getStatus();

  /// 请求打开系统通知设置页；无法打开时返回 false，不抛出。
  Future<bool> openSettings();
}

/// 生产端口必须由 app composition 绑定（Android/Windows adapter 或 no-op）。
final systemNotificationSettingsProvider = Provider<SystemNotificationSettings>(
  (ref) => throw UnsupportedError('系统通知设置必须由 app composition 绑定'),
);

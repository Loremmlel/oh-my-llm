import 'dart:async';

/// 网络日志接口：用于记录请求、响应、流式行与异常。
///
/// 所有方法均有默认 no-op 实现，使用者只需 override 需要的方法。
mixin NetworkLogger {
  Future<void> onAppLaunch() async {}

  Future<void> onAppDetached() async {}

  Future<void> logRequest({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Object? payload,
  }) async {}

  Future<void> logResponse({
    required Uri uri,
    required int statusCode,
    required Map<String, String> headers,
    required Duration elapsed,
  }) async {}

  Future<void> logResponseBody({required Uri uri, required Object? body}) async {}

  Future<void> logSseLine({required Uri uri, required String line}) async {}

  Future<void> logError({
    required Uri uri,
    required Object error,
    StackTrace? stackTrace,
  }) async {}
}

/// 空操作日志实现——所有方法均为 no-op。
///
/// 用于不需要日志的场景（如测试、禁用日志时）。
final class NoopNetworkLogger with NetworkLogger {
  const NoopNetworkLogger();
}

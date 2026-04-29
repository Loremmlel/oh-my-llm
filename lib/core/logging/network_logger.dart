import 'dart:async';

/// 网络日志接口：用于记录请求、响应、流式行与异常。
abstract interface class NetworkLogger {
  Future<void> onAppLaunch();

  Future<void> onAppDetached();

  Future<void> logRequest({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Object? payload,
  });

  Future<void> logResponse({
    required Uri uri,
    required int statusCode,
    required Map<String, String> headers,
    required Duration elapsed,
  });

  Future<void> logSseLine({required Uri uri, required String line});

  Future<void> logError({
    required Uri uri,
    required Object error,
    StackTrace? stackTrace,
  });
}

final class NoopNetworkLogger implements NetworkLogger {
  const NoopNetworkLogger();

  @override
  Future<void> onAppLaunch() async {}

  @override
  Future<void> onAppDetached() async {}

  @override
  Future<void> logRequest({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Object? payload,
  }) async {}

  @override
  Future<void> logResponse({
    required Uri uri,
    required int statusCode,
    required Map<String, String> headers,
    required Duration elapsed,
  }) async {}

  @override
  Future<void> logSseLine({required Uri uri, required String line}) async {}

  @override
  Future<void> logError({
    required Uri uri,
    required Object error,
    StackTrace? stackTrace,
  }) async {}
}

import 'dart:convert';
import 'dart:io';

import 'app_log_store.dart';
import 'json_truncator.dart';
import 'network_log_redactor.dart';
import 'network_logger.dart';

/// 应用级网络日志实现，仅依赖文件阈值轮转，不在退出或重启时主动清空。
final class AppNetworkLogger with NetworkLogger {
  AppNetworkLogger({
    required AppLogStore store,
    NetworkLogRedactor redactor = const NetworkLogRedactor(),
  }) : _store = store,
       _redactor = redactor;

  final AppLogStore _store;
  final NetworkLogRedactor _redactor;

  static Future<AppNetworkLogger> create({
    required String directoryPath,
  }) async {
    final store = await AppLogStore.open(directoryPath: directoryPath);
    return AppNetworkLogger(store: store);
  }

  @override
  Future<void> onAppLaunch() async {
    await _writeLog('[app-launch] logger initialized.');
  }

  @override
  Future<void> logRequest({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Object? payload,
  }) async {
    final h = _redactor.redactHeaders(headers);
    final p = truncateJsonValues(_redactor.redactPayload(payload));
    await _writeLog(
      '[request] $method $uri headers=${jsonEncode(h)} payload=${jsonEncode(p)}',
    );
  }

  @override
  Future<void> logResponse({
    required Uri uri,
    required int statusCode,
    required Map<String, String> headers,
    required Duration elapsed,
  }) async {
    final h = _redactor.redactHeaders(headers);
    await _writeLog(
      '[response] $uri status=$statusCode elapsedMs=${elapsed.inMilliseconds}'
      ' headers=${jsonEncode(h)}',
    );
  }

  @override
  Future<void> logResponseBody({
    required Uri uri,
    required Object? body,
  }) async {
    final redactedBody = _redactor.redactPayload(body);
    final truncatedBody = redactedBody is String
        ? _truncateText(redactedBody)
        : truncateJsonValues(redactedBody);
    final serialized = truncatedBody is String
        ? truncatedBody
        : jsonEncode(truncatedBody);
    await _writeLog('[response-body] $uri body=$serialized');
  }

  @override
  Future<void> logSseLine({required Uri uri, required String line}) async {
    String processLine(String s) {
      try {
        return jsonEncode(truncateJsonValues(jsonDecode(s)));
      } catch (_) {
        return _truncateText(s);
      }
    }

    await _writeLog('[sse] $uri ${_redactor.redactText(processLine(line))}');
  }

  @override
  Future<void> logError({
    required Uri uri,
    required Object error,
    StackTrace? stackTrace,
  }) async {
    await _writeLog('[error] $uri ${_redactor.redactText(error.toString())}');
    if (stackTrace != null) {
      for (final stackLine in stackTrace.toString().split('\n').take(12)) {
        await _writeLog('  $stackLine');
      }
    }
  }

  // ── 内部方法 ──────────────────────────────────────────────────────

  Future<void> _writeLog(String line) async {
    try {
      await _store.appendLine('[${DateTime.now().toIso8601String()}] $line');
    } catch (error, stackTrace) {
      stderr.writeln('[network-log] write failed: $error\n$stackTrace');
    }
  }

  String _truncateText(String s) {
    if (s.length <= defaultMaxLogValueLength) return s;
    return '${s.substring(0, defaultMaxLogValueLength)}...[truncated]';
  }
}

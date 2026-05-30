import 'dart:convert';
import 'dart:io';

import 'app_log_store.dart';
import 'json_truncator.dart';
import 'network_log_redactor.dart';
import 'network_logger.dart';

/// 应用级网络日志实现，仅依赖文件阈值轮转，不在退出或重启时主动清空。
final class AppNetworkLogger implements NetworkLogger {
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
    try {
      final now = DateTime.now().toIso8601String();
      await _store.appendLine('[$now] [app-launch] logger initialized.');
    } catch (error, stackTrace) {
      stderr.writeln('[network-log] launch init failed: $error\n$stackTrace');
    }
  }

  @override
  Future<void> onAppDetached() async {}

  @override
  Future<void> logRequest({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Object? payload,
  }) async {
    await _safeWrite(() async {
      final redactedHeaders = _redactor.redactHeaders(headers);
      final redactedPayload = _redactor.redactPayload(payload);
      final truncatedPayload = truncateJsonValues(redactedPayload);
      await _store.appendLine(
        '[${DateTime.now().toIso8601String()}] [request] $method $uri'
        ' headers=${_redactor.toJson(redactedHeaders)}'
        ' payload=${_redactor.toJson(truncatedPayload)}',
      );
    });
  }

  @override
  Future<void> logResponse({
    required Uri uri,
    required int statusCode,
    required Map<String, String> headers,
    required Duration elapsed,
  }) async {
    await _safeWrite(() async {
      final redactedHeaders = _redactor.redactHeaders(headers);
      await _store.appendLine(
        '[${DateTime.now().toIso8601String()}] [response] $uri'
        ' status=$statusCode elapsedMs=${elapsed.inMilliseconds}'
        ' headers=${jsonEncode(redactedHeaders)}',
      );
    });
  }

  @override
  Future<void> logResponseBody({
    required Uri uri,
    required Object? body,
  }) async {
    await _safeWrite(() async {
      final redactedBody = _redactor.redactPayload(body);
      final truncatedBody = redactedBody is String
          ? (redactedBody.length > 500 ? '${redactedBody.substring(0, 500)}...[truncated]' : redactedBody)
          : truncateJsonValues(redactedBody);
      final serializedBody = truncatedBody is String
          ? truncatedBody
          : _redactor.toJson(truncatedBody);
      await _store.appendLine(
        '[${DateTime.now().toIso8601String()}] [response-body] $uri'
        ' body=$serializedBody',
      );
    });
  }

  @override
  Future<void> logSseLine({required Uri uri, required String line}) async {
    await _safeWrite(() async {
      String processLine(String line) {
        try {
          final decoded = jsonDecode(line);
          final truncated = truncateJsonValues(decoded);
          return jsonEncode(truncated);
        } catch (_) {
          return line.length > 500 ? '${line.substring(0, 500)}...[truncated]' : line;
        }
      }
      final processed = processLine(line);
      await _store.appendLine(
        '[${DateTime.now().toIso8601String()}] [sse] $uri ${_redactor.redactText(processed)}',
      );
    });
  }

  @override
  Future<void> logError({
    required Uri uri,
    required Object error,
    StackTrace? stackTrace,
  }) async {
    await _safeWrite(() async {
      final message = _redactor.redactText(error.toString());
      await _store.appendLine(
        '[${DateTime.now().toIso8601String()}] [error] $uri $message',
      );
      if (stackTrace != null) {
        final stackLines = stackTrace.toString().split('\n');
        for (final stackLine in stackLines.take(12)) {
          await _store.appendLine('  $stackLine');
        }
      }
    });
  }

  Future<void> _safeWrite(Future<void> Function() callback) async {
    try {
      await callback();
    } catch (error, stackTrace) {
      stderr.writeln('[network-log] write failed: $error\n$stackTrace');
    }
  }
}

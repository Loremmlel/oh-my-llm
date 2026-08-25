import 'dart:convert';
import 'dart:io';

import 'package:characters/characters.dart';

import 'app_log_store.dart';
import 'json_truncator.dart';
import 'network_log_redactor.dart';
import 'network_logger.dart';
import 'sse_log_buffer.dart';

/// 应用级网络日志实现，仅依赖文件阈值轮转，不在退出或重启时主动清空。
final class AppNetworkLogger with NetworkLogger {
  AppNetworkLogger({
    required AppLogStore store,
    this._redactor = const NetworkLogRedactor(),
  }) : _store = store,
       _sseBuffer = SseLogBuffer(store: store);

  final AppLogStore _store;
  final NetworkLogRedactor _redactor;
  final SseLogBuffer _sseBuffer;

  static Future<AppNetworkLogger> create({
    required String directoryPath,
  }) async {
    final store = await AppLogStore.open(directoryPath: directoryPath);
    final logger = AppNetworkLogger(store: store);
    logger._sseBuffer.startPeriodicFlush();
    return logger;
  }

  @override
  Future<void> onAppLaunch() async {
    await _writeLog('[app-launch] logger initialized.');
  }

  @override
  Future<void> onAppDetached() async {
    await drain();
  }

  @override
  Future<void> logRequest({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Object? payload,
    bool logBody = false,
  }) async {
    final h = _redactor.redactHeaders(headers);
    if (logBody) {
      final p = truncateJsonValues(_redactor.redactPayload(payload));
      await _writeLog(
        '[request] $method $uri headers=${jsonEncode(h)} payload=${jsonEncode(p)}',
      );
    } else {
      await _writeLog('[request] $method $uri headers=${jsonEncode(h)}');
    }
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
    bool logBody = false,
  }) async {
    if (!logBody) return;

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

    final now = DateTime.now().toIso8601String();
    final processed = _redactor.redactText(processLine(line));
    _sseBuffer.enqueue('[$now] [sse] $uri $processed');
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

  @override
  Future<void> drain() async {
    await _sseBuffer.drain();
    await _writeLog('[drain] SSE buffer flushed.');
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
    final characters = s.characters;
    if (characters.length <= defaultMaxLogValueLength) return s;
    return '${characters.take(defaultMaxLogValueLength).toString()}...[truncated]';
  }
}

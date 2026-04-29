import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_log_store.dart';
import 'network_log_redactor.dart';
import 'network_logger.dart';

/// 应用级网络日志实现，支持启动恢复清理、阈值轮转与生命周期清理。
final class AppNetworkLogger implements NetworkLogger {
  AppNetworkLogger({
    required AppLogStore store,
    required SharedPreferences preferences,
    NetworkLogRedactor redactor = const NetworkLogRedactor(),
  }) : _store = store,
       _preferences = preferences,
       _redactor = redactor;

  static const cleanShutdownMarkerKey = 'network_log_clean_shutdown';
  static const initializedMarkerKey = 'network_log_initialized';

  final AppLogStore _store;
  final SharedPreferences _preferences;
  final NetworkLogRedactor _redactor;

  static Future<AppNetworkLogger> create({
    required String directoryPath,
    required SharedPreferences preferences,
  }) async {
    final store = await AppLogStore.open(directoryPath: directoryPath);
    return AppNetworkLogger(store: store, preferences: preferences);
  }

  @override
  Future<void> onAppLaunch() async {
    try {
      final hasInitialized =
          _preferences.getBool(initializedMarkerKey) ?? false;
      final cleanShutdown =
          _preferences.getBool(cleanShutdownMarkerKey) ?? true;
      if (hasInitialized && !cleanShutdown) {
        await _store.clear(reason: 'recovered from unclean shutdown');
      }
      final now = DateTime.now().toIso8601String();
      await _store.appendLine('[$now] [app-launch] logger initialized.');
      await _preferences.setBool(initializedMarkerKey, true);
      await _preferences.setBool(cleanShutdownMarkerKey, false);
    } catch (error, stackTrace) {
      stderr.writeln('[network-log] launch init failed: $error\n$stackTrace');
    }
  }

  @override
  Future<void> onAppDetached() async {
    try {
      await _store.clear(reason: 'app detached');
      await _preferences.setBool(cleanShutdownMarkerKey, true);
    } catch (error, stackTrace) {
      stderr.writeln(
        '[network-log] detached cleanup failed: $error\n$stackTrace',
      );
    }
  }

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
      await _store.appendLine(
        '[${DateTime.now().toIso8601String()}] [request] $method $uri'
        ' headers=${_redactor.toJson(redactedHeaders)}'
        ' payload=${_redactor.toJson(redactedPayload)}',
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
  Future<void> logSseLine({required Uri uri, required String line}) async {
    await _safeWrite(() async {
      final trimmed = line.length > 1000 ? '${line.substring(0, 1000)}…' : line;
      await _store.appendLine(
        '[${DateTime.now().toIso8601String()}] [sse] $uri ${_redactor.redactText(trimmed)}',
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

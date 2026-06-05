import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/models/sync_message.dart';
import '../domain/models/sync_types.dart';

/// 同步 HTTP 服务端封装。
///
/// 绑定到 OS 分配的随机端口，监听 `POST /sync` 请求，
/// 请求体和响应体均为 [SyncMessage] JSON。
class SyncHttpServer {
  HttpServer? _server;

  bool get isRunning => _server != null;

  /// 启动 HTTP 服务端，返回分配的端口号。
  ///
  /// [onRequest] 在每次收到 `POST /sync` 请求时被调用，
  /// 接收解析后的 [SyncMessage]，需返回响应 [SyncMessage]。
  Future<int> start({
    required Future<SyncMessage> Function(SyncMessage request) onRequest,
  }) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);

    final server = _server!;

    server.listen((request) async {
      if (request.method != 'POST' || request.uri.path != '/sync') {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
        return;
      }

      try {
        final body = await utf8.decoder.bind(request).join();
        final message = SyncMessageCodec.tryDecode(body);
        if (message == null) {
          final error = SyncMessage.error(
            requestId: '',
            code: SyncErrorCode.payloadParseFailed,
            message: '请求格式错误',
          );
          _writeJsonResponse(request, error);
          return;
        }

        final response = await onRequest(message);
        _writeJsonResponse(request, response);
      } catch (e) {
        debugPrint('同步服务端处理异常: $e');
        final error = SyncMessage.error(
          requestId: '',
          code: SyncErrorCode.payloadParseFailed,
          message: '服务端处理异常',
        );
        _writeJsonResponse(request, error);
      }
    });

    return server.port;
  }

  void _writeJsonResponse(HttpRequest request, SyncMessage message) {
    final body = SyncMessageCodec.encode(message);
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(body)
      ..close();
  }

  /// 停止服务端并关闭所有连接。
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}

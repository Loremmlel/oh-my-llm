import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:oh_my_llm/core/http/http_route_handler.dart';

import '../domain/models/sync_message.dart';
import '../domain/models/sync_types.dart';

/// 处理 `POST /sync` 请求的 Handler。
///
/// 从原 [SyncHttpServer] 的 listen 回调中提取出同步业务逻辑，
/// 实现 [HttpRouteHandler] 接口，与 [MediaHttpHandler] 平等挂载到路由器上。
class SyncHttpHandler implements HttpRouteHandler {
  final Future<SyncMessage> Function(SyncMessage) onRequest;

  SyncHttpHandler({required this.onRequest});

  @override
  bool canHandle(HttpRequest request) =>
      request.method == 'POST' && request.uri.path == '/sync';

  @override
  Future<void> handle(HttpRequest request) async {
    try {
      final body = await utf8.decoder
          .bind(request)
          .join()
          .timeout(const Duration(seconds: 30));
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

      final response =
          await onRequest(message).timeout(const Duration(seconds: 15));
      _writeJsonResponse(request, response);
    } on TimeoutException {
      final error = SyncMessage.error(
        requestId: '',
        code: SyncErrorCode.timeout,
        message: '请求处理超时',
      );
      _writeJsonResponse(request, error);
    } catch (e) {
      debugPrint('同步服务端处理异常: $e');
      final error = SyncMessage.error(
        requestId: '',
        code: SyncErrorCode.payloadParseFailed,
        message: '服务端处理异常',
      );
      _writeJsonResponse(request, error);
    }
  }

  void _writeJsonResponse(HttpRequest request, SyncMessage message) {
    final body = SyncMessageCodec.encode(message);
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(body)
      ..close();
  }
}

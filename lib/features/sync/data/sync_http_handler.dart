import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:oh_my_llm/core/http/http_route_handler.dart';

import '../domain/models/sync_protocol_failure.dart';
import '../domain/models/sync_protocol_message.dart';

/// 处理 `POST /sync` 请求的 Handler。
///
/// 从原 [SyncHttpServer] 的 listen 回调中提取出同步业务逻辑，
/// 实现 [HttpRouteHandler] 接口，与 [MediaHttpHandler] 平等挂载到路由器上。
class SyncHttpHandler implements HttpRouteHandler {
  final Future<SyncProtocolMessage> Function(SyncProtocolMessage) onRequest;

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
      final decoded = SyncProtocolCodec.decode(body);
      if (decoded case SyncProtocolDecodeFailure(:final failure)) {
        _writeJsonResponse(
          request,
          SyncProtocolError(requestId: '', failure: failure),
        );
        return;
      }

      final response = await onRequest(
        (decoded as SyncProtocolDecodeSuccess).message,
      ).timeout(const Duration(seconds: 15));
      _writeJsonResponse(request, response);
    } on TimeoutException {
      _writeJsonResponse(
        request,
        const SyncProtocolError(
          requestId: '',
          failure: SyncProtocolFailure(SyncProtocolErrorCode.requestTimedOut),
        ),
      );
    } catch (_) {
      _writeJsonResponse(
        request,
        const SyncProtocolError(
          requestId: '',
          failure: SyncProtocolFailure(SyncProtocolErrorCode.serverBusy),
        ),
      );
    }
  }

  void _writeJsonResponse(HttpRequest request, SyncProtocolMessage message) {
    final body = SyncProtocolCodec.encode(message);
    request.response
      ..statusCode = _statusFor(message)
      ..headers.contentType = ContentType.json
      ..write(body)
      ..close();
  }

  int _statusFor(SyncProtocolMessage message) {
    if (message case SyncProtocolError(:final failure)) {
      return switch (failure.code) {
        SyncProtocolErrorCode.malformedMessage => HttpStatus.badRequest,
        SyncProtocolErrorCode.unsupportedProtocol => HttpStatus.upgradeRequired,
        SyncProtocolErrorCode.pairingRequired ||
        SyncProtocolErrorCode.pairingRejected ||
        SyncProtocolErrorCode.sessionInvalid ||
        SyncProtocolErrorCode.sessionExpired ||
        SyncProtocolErrorCode.replayRejected => HttpStatus.unauthorized,
        SyncProtocolErrorCode.authorizationRequired ||
        SyncProtocolErrorCode.sensitiveConfirmationRequired =>
          HttpStatus.forbidden,
        SyncProtocolErrorCode.unsupportedSettingsFormat =>
          HttpStatus.unprocessableEntity,
        SyncProtocolErrorCode.requestTimedOut => HttpStatus.requestTimeout,
        SyncProtocolErrorCode.serverBusy => HttpStatus.serviceUnavailable,
      };
    }
    return HttpStatus.ok;
  }
}

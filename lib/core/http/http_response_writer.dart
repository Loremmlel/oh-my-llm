import 'dart:convert';
import 'dart:io';

/// HTTP 响应写入工具。
///
/// 提供统一的 JSON 错误响应写入，包含 CORS 头。
/// 供所有 [HttpRouteHandler] 共用，避免在每个 Handler 中重复 `_writeError`。

/// 写入 JSON 错误响应，统一设置 CORS 头。
///
/// [statusCode] HTTP 状态码。
/// [message] 错误消息（写入 `{"error": message}`）。
void writeJsonError(HttpResponse response, int statusCode, String message) {
  response
    ..statusCode = statusCode
    ..headers.contentType = ContentType.json
    ..headers.set('Access-Control-Allow-Origin', '*')
    ..write(jsonEncode({'error': message}))
    ..close();
}

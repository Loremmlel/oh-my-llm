/// 网络日志脱敏工具：对敏感 Header 和载荷字段做遮罩。
///
/// 安全默认策略：
/// - 敏感 Header 键（authorization / cookie / token / secret 等）的值替换为 `***`
/// - 敏感 JSON 字段（apikey / token / secret / password / credential）的值替换为 `***`
/// - Bearer token 内联文本遮罩
///
/// 扩展新敏感模式时，更新 [_sensitiveHeaderKeys] 和 [_sensitivePayloadKeys] 即可。
final class NetworkLogRedactor {
  static final RegExp _bearerPattern = RegExp(
    r'(Bearer\s+)([^\s",]+)',
    caseSensitive: false,
  );

  static final RegExp _apiKeyFieldPattern = RegExp(
    r'("api(?:_|)key"\s*:\s*")([^"]+)(")',
    caseSensitive: false,
  );

  /// 敏感 Header 键名集合（小写，用于 contains 匹配）。
  ///
  /// 任何包含这些子串的 Header 键，其值都会被遮罩。
  /// 例如 `X-Proxy-Authorization` 包含 `authorization`，会被遮罩。
  static const _sensitiveHeaderKeys = <String>{
    'authorization',
    'cookie',
    'x-api-key',
    'token',
    'secret',
  };

  /// 敏感 JSON 载荷字段名集合（小写，用于精确匹配）。
  static const _sensitivePayloadKeys = <String>{
    'apikey',
    'api_key',
    'token',
    'secret',
    'password',
    'credential',
  };

  const NetworkLogRedactor();

  /// 判断 [key] 是否为敏感 Header 键。
  ///
  /// 公开方法，供测试断言使用。
  bool isSensitiveHeader(String key) {
    final normalized = key.toLowerCase();
    return _sensitiveHeaderKeys.any(normalized.contains);
  }

  Map<String, String> redactHeaders(Map<String, String> headers) {
    final redacted = <String, String>{};
    for (final entry in headers.entries) {
      if (isSensitiveHeader(entry.key)) {
        redacted[entry.key] = '***';
        continue;
      }
      redacted[entry.key] = entry.value;
    }
    return redacted;
  }

  Object? redactPayload(Object? payload) {
    if (payload == null) {
      return null;
    }
    if (payload is Map) {
      return payload.map((key, value) {
        final keyString = key.toString();
        if (_looksLikeSensitiveField(keyString)) {
          return MapEntry(keyString, '***');
        }
        return MapEntry(keyString, redactPayload(value));
      });
    }
    if (payload is List) {
      return payload.map(redactPayload).toList(growable: false);
    }
    if (payload is String) {
      return redactText(payload);
    }
    return payload;
  }

  String redactText(String text) {
    final bearerRedacted = _redactBearer(text);
    return bearerRedacted.replaceAllMapped(_apiKeyFieldPattern, (match) {
      return '${match.group(1)}***${match.group(3)}';
    });
  }

  bool _looksLikeSensitiveField(String key) {
    final normalized = key.toLowerCase();
    return _sensitivePayloadKeys.contains(normalized);
  }

  String _redactBearer(String value) {
    return value.replaceAllMapped(_bearerPattern, (match) {
      return '${match.group(1)}***';
    });
  }
}

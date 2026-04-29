import 'dart:convert';

/// 网络日志脱敏工具：仅对 API Key（含 Bearer token）做遮罩。
final class NetworkLogRedactor {
  static final RegExp _bearerPattern = RegExp(
    r'(Bearer\s+)([^\s",]+)',
    caseSensitive: false,
  );

  static final RegExp _apiKeyFieldPattern = RegExp(
    r'("api(?:_|)key"\s*:\s*")([^"]+)(")',
    caseSensitive: false,
  );

  const NetworkLogRedactor();

  Map<String, String> redactHeaders(Map<String, String> headers) {
    final redacted = <String, String>{};
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'authorization') {
        redacted[entry.key] = _redactBearer(entry.value);
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
        if (_looksLikeApiKeyField(keyString)) {
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

  String toJson(Object? value) {
    return jsonEncode(value);
  }

  bool _looksLikeApiKeyField(String key) {
    final normalized = key.toLowerCase();
    return normalized == 'apikey' || normalized == 'api_key';
  }

  String _redactBearer(String value) {
    return value.replaceAllMapped(_bearerPattern, (match) {
      return '${match.group(1)}***';
    });
  }
}

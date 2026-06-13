import 'package:http/http.dart' as http;

/// 自定义 HTTP 请求头注入客户端。
///
/// 包装 [http.Client]，在每次调用 [send] 时将用户定义的请求头
/// 注入到 [http.BaseRequest] 中。注入发生在调用方已设置完 header 之后，
/// 因此同名 header 会以用户定义为准，覆盖应用默认值和 Flutter 默认值。
///
/// 注意：[Host] 请求头可能被 dart:io 底层 [HttpClient] 基于 URL 强制覆盖。
class CustomHeadersHttpClient extends http.BaseClient {
  CustomHeadersHttpClient(this._inner, Map<String, String> initialHeaders)
      : _headers = Map<String, String>.from(initialHeaders);

  final http.Client _inner;
  Map<String, String> _headers;
  bool _isClosed = false;

  /// 原地更新 header 映射，无需重建 client 实例。
  void updateHeaders(Map<String, String> headers) {
    _headers = Map<String, String>.from(headers);
  }

  /// 当前生效的 header 映射。
  Map<String, String> get currentHeaders => Map<String, String>.unmodifiable(_headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_isClosed) {
      throw http.ClientException(
        'CustomHeadersHttpClient: 无法发送请求，client 已关闭。',
        request.url,
      );
    }
    // 在调用方已设置 header 之后覆盖写入，确保用户定义优先。
    for (final entry in _headers.entries) {
      request.headers[entry.key] = entry.value;
    }
    return _inner.send(request);
  }

  @override
  void close() {
    _isClosed = true;
    _inner.close();
  }
}

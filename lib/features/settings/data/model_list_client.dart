import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/http/http_client_provider.dart';
import '../../../core/logging/app_network_logger_provider.dart';
import '../../../core/logging/network_logger.dart';

/// 从 /models 端点拉取的模型信息（传输对象，不持久化）。
class RemoteModelInfo {
  const RemoteModelInfo({required this.id, this.ownedBy});

  final String id;

  final String? ownedBy;
}

/// 拉取模型列表失败时抛出的业务异常。
class ModelListException implements Exception {
  const ModelListException(
    this.message, {
    this.statusCode,
    this.responseBody,
    this.cause,
  });

  final String message;

  final int? statusCode;

  final String? responseBody;

  final Object? cause;

  @override
  String toString() => message;
}

/// 获取模型列表的 HTTP 客户端 Provider。
final modelListClientProvider = Provider<ModelListClient>((ref) {
  return ModelListClient(
    httpClient: ref.watch(httpClientProvider),
    logger: ref.watch(appNetworkLoggerProvider),
  );
});

/// 通过 GET /models 端点拉取服务器可用模型列表。
///
/// 仅支持 OpenAI 标准格式：`{object: "list", data: [{id, ...}]}`。
class ModelListClient {
  ModelListClient({
    required http.Client httpClient,
    NetworkLogger logger = const NoopNetworkLogger(),
  })  : _httpClient = httpClient,
        _logger = logger;

  final http.Client _httpClient;
  final NetworkLogger _logger;

  /// 拉取模型列表。
  ///
  /// [modelsUrl] 是推导后的 models 端点 URL。
  /// [apiKey] 用于 Authorization: Bearer 认证。
  Future<List<RemoteModelInfo>> fetchModels({
    required String modelsUrl,
    required String apiKey,
  }) async {
    Uri uri;
    try {
      uri = Uri.parse(modelsUrl);
    } on FormatException catch (e) {
      throw ModelListException('API URL 格式无效：${e.message}');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ModelListException(
        'API URL 格式无效（需要 http/https）：$modelsUrl',
      );
    }

    await _logger.logRequest(
      uri: uri,
      method: 'GET',
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Accept': 'application/json',
      },
      payload: null,
    );

    http.Response response;
    try {
      response = await _httpClient.get(
        uri,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));
    } on http.ClientException catch (e) {
      await _logger.logError(uri: uri, error: e, stackTrace: StackTrace.current);
      throw ModelListException('网络请求失败：${e.message}', cause: e);
    } catch (e) {
      await _logger.logError(uri: uri, error: e, stackTrace: StackTrace.current);
      throw ModelListException('网络请求失败：$e', cause: e);
    }

    await _logger.logResponse(
      uri: uri,
      statusCode: response.statusCode,
      headers: response.headers,
      elapsed: Duration.zero,
    );

    if (response.statusCode != 200) {
      throw ModelListException(
        '服务器返回错误（${response.statusCode}）',
        statusCode: response.statusCode,
        responseBody: _truncateBody(response.body),
      );
    }

    final List<dynamic> data;
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      data = json['data'] as List<dynamic>? ?? const [];
    } catch (e) {
      throw ModelListException(
        '响应解析失败',
        responseBody: _truncateBody(response.body),
        cause: e,
      );
    }

    final models = <RemoteModelInfo>[];
    for (final item in data) {
      try {
        final map = item as Map<String, dynamic>;
        final id = map['id'];
        if (id is! String || id.isEmpty) continue;
        models.add(RemoteModelInfo(
          id: id,
          ownedBy: map['owned_by'] as String?,
        ));
      } catch (_) {
        // 跳过格式异常的条目，而非整个列表失败
        continue;
      }
    }
    return models;
  }
}

/// 截断响应体到指定长度，超长时追加省略号。
String _truncateBody(String body, [int max = 200]) {
  if (body.length > max) return '${body.substring(0, max)}...';
  return body;
}

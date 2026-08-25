import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:oh_my_llm/core/http/custom_headers_provider.dart';
import 'package:oh_my_llm/core/http/http_client_provider.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/logging/app_network_logger_provider.dart';
import 'package:oh_my_llm/core/logging/json_truncator.dart';
import 'package:oh_my_llm/core/logging/network_logger.dart';

import '../../domain/models/providers/model_catalog_entry.dart';

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
    extraHeadersFactory: () => ref.read(customHeadersMapProvider),
  );
});

/// 通过 GET /models 端点拉取服务器可用模型列表。
///
/// 仅支持 OpenAI 标准格式：`{object: "list", data: [{id, ...}]}`。
class ModelListClient {
  ModelListClient({
    required http.Client httpClient,
    NetworkLogger logger = const NoopNetworkLogger(),
    Map<String, String> Function()? extraHeadersFactory,
  }) : _httpClient = httpClient,
       _logger = logger,
       _extraHeadersFactory = extraHeadersFactory;

  final http.Client _httpClient;
  final NetworkLogger _logger;
  final Map<String, String> Function()? _extraHeadersFactory;

  /// 拉取模型列表。
  ///
  /// [modelsUrl] 是推导后的 models 端点 URL。
  /// [apiProtocol] 决定认证 Header：Chat Completions / Responses 用
  /// `Authorization: Bearer`，Anthropic 用 `x-api-key` + `anthropic-version`。
  Future<List<ModelCatalogEntry>> fetchModels({
    required String modelsUrl,
    required String apiKey,
    required LlmApiProtocol apiProtocol,
  }) async {
    Uri uri;
    try {
      uri = Uri.parse(modelsUrl);
    } on FormatException catch (e) {
      throw ModelListException('API URL 格式无效：${e.message}');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ModelListException('API URL 格式无效（需要 http/https）：$modelsUrl');
    }

    final requestHeaders = switch (apiProtocol) {
      LlmApiProtocol.chatCompletions || LlmApiProtocol.responses => {
        'Authorization': 'Bearer $apiKey',
        'Accept': 'application/json',
      },
      LlmApiProtocol.anthropic => {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'Accept': 'application/json',
      },
    };
    final effectiveRequestHeaders = _mergeHeadersCaseInsensitive(
      requestHeaders,
      _extraHeadersFactory?.call() ?? const <String, String>{},
    );

    _fireAndForget(
      _logger.logRequest(
        uri: uri,
        method: 'GET',
        headers: effectiveRequestHeaders,
        payload: null,
        logBody: false,
      ),
    );

    final requestStartedAt = DateTime.now();
    http.Response response;
    try {
      response = await _httpClient
          .get(uri, headers: requestHeaders)
          .timeout(const Duration(seconds: 30));
    } on http.ClientException catch (e) {
      await _logger.logError(
        uri: uri,
        error: e,
        stackTrace: StackTrace.current,
      );
      throw ModelListException('网络请求失败：${e.message}', cause: e);
    } catch (e) {
      await _logger.logError(
        uri: uri,
        error: e,
        stackTrace: StackTrace.current,
      );
      throw ModelListException('网络请求失败：$e', cause: e);
    }

    final elapsed = DateTime.now().difference(requestStartedAt);
    _fireAndForget(
      _logger.logResponse(
        uri: uri,
        statusCode: response.statusCode,
        headers: response.headers,
        elapsed: elapsed,
      ),
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

    final models = <ModelCatalogEntry>[];
    for (final item in data) {
      try {
        final map = item as Map<String, dynamic>;
        final id = map['id'];
        if (id is! String || id.isEmpty) continue;
        models.add(
          ModelCatalogEntry(id: id, ownedBy: map['owned_by'] as String?),
        );
      } catch (_) {
        // 跳过格式异常的条目，而非整个列表失败
        continue;
      }
    }
    return models;
  }

  void _fireAndForget(Future<void> future) {
    unawaited(future);
  }

  /// 按 HTTP Header 大小写不敏感语义合并，后者覆盖前者。
  Map<String, String> _mergeHeadersCaseInsensitive(
    Map<String, String> defaults,
    Map<String, String> overrides,
  ) {
    final result = <String, String>{...defaults};
    final keyByLowerName = <String, String>{
      for (final key in result.keys) key.toLowerCase(): key,
    };
    for (final entry in overrides.entries) {
      final lowerName = entry.key.toLowerCase();
      final oldKey = keyByLowerName[lowerName];
      if (oldKey != null) result.remove(oldKey);
      result[entry.key] = entry.value;
      keyByLowerName[lowerName] = entry.key;
    }
    return result;
  }

  /// 截断响应体到指定长度，使用 grapheme-aware 截断。
  String _truncateBody(String body) {
    final truncated = truncateJsonValues(body, maxLength: 200);
    return truncated as String;
  }
}

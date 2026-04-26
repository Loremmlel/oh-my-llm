import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../settings/domain/models/llm_model_config.dart';
import '../domain/models/chat_message.dart';
import 'chat_completion_client.dart';

final chatCompletionClientProvider = Provider<ChatCompletionClient>((ref) {
  final httpClient = http.Client();
  ref.onDispose(httpClient.close);
  return OpenAiCompatibleChatClient(httpClient: httpClient);
});

class OpenAiCompatibleChatClient implements ChatCompletionClient {
  OpenAiCompatibleChatClient({
    required http.Client httpClient,
  }) : _httpClient = httpClient;

  final http.Client _httpClient;

  @override
  Stream<String> streamCompletion({
    required LlmModelConfig modelConfig,
    required List<ChatCompletionRequestMessage> messages,
    ReasoningEffort? reasoningEffort,
  }) async* {
    final uri = Uri.tryParse(modelConfig.apiUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const ChatCompletionException('API URL 无效，请在设置页检查模型配置。');
    }
    final thinkingConfig = _buildThinkingConfig(
      uri,
      enabled: reasoningEffort != null,
    );
    final payload = <String, Object>{
      'model': modelConfig.modelName,
      'stream': true,
      'messages': messages.map((message) => message.toJson()).toList(),
      if (reasoningEffort != null)
        'reasoning_effort': _buildReasoningEffort(uri, reasoningEffort),
    };
    if (thinkingConfig != null) {
      payload['thinking'] = thinkingConfig;
    }

    final request = http.Request('POST', uri)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'Authorization': 'Bearer ${modelConfig.apiKey}',
      })
      ..body = jsonEncode(payload);

    final response = await _httpClient.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final responseBody = await response.stream.bytesToString();
      throw ChatCompletionException(
        '请求失败（${response.statusCode}）：${responseBody.trim().isEmpty ? '服务端未返回错误详情' : responseBody.trim()}',
      );
    }

    final lineStream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    final dataLines = <String>[];

    await for (final line in lineStream) {
      if (line.isEmpty) {
        final chunk = _consumeEventData(dataLines);
        if (chunk == null) {
          continue;
        }
        if (chunk == _doneMarker) {
          break;
        }

        yield _parseChunk(chunk);
        continue;
      }

      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }

    final trailingChunk = _consumeEventData(dataLines);
    if (trailingChunk != null && trailingChunk != _doneMarker) {
      yield _parseChunk(trailingChunk);
    }
  }

  static const _doneMarker = '[DONE]';

  String? _consumeEventData(List<String> dataLines) {
    if (dataLines.isEmpty) {
      return null;
    }

    final eventData = dataLines.join('\n').trim();
    dataLines.clear();

    if (eventData.isEmpty) {
      return null;
    }

    return eventData;
  }

  String _parseChunk(String rawChunk) {
    late final Object? decoded;
    try {
      decoded = jsonDecode(rawChunk);
    } on FormatException {
      throw const ChatCompletionException('服务端返回了无法解析的流式数据。');
    }

    if (decoded is! Map) {
      return '';
    }

    final error = decoded['error'];
    if (error is String && error.trim().isNotEmpty) {
      throw ChatCompletionException(error.trim());
    }
    if (error is Map) {
      final message = error['message'];
      if (message is String && message.trim().isNotEmpty) {
        throw ChatCompletionException(message.trim());
      }
    }

    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return '';
    }

    final firstChoice = Map<String, dynamic>.from(choices.first as Map);
    final delta = firstChoice['delta'] ?? firstChoice['message'];
    return _extractContent(delta);
  }

  String _extractContent(Object? payload) {
    if (payload is String) {
      return payload;
    }
    if (payload is! Map) {
      return '';
    }

    final content = payload['content'];
    if (content is String) {
      return content;
    }
    if (content is List) {
      return content.map(_extractSegmentText).join();
    }

    final reasoningContent = payload['reasoning_content'];
    if (reasoningContent is String) {
      return reasoningContent;
    }

    return '';
  }

  String _extractSegmentText(Object? segment) {
    if (segment is String) {
      return segment;
    }
    if (segment is! Map) {
      return '';
    }

    final text = segment['text'];
    if (text is String) {
      return text;
    }

    final nestedText = segment['content'];
    if (nestedText is String) {
      return nestedText;
    }

    return '';
  }

  Map<String, String>? _buildThinkingConfig(Uri uri, {required bool enabled}) {
    if (_isOfficialOpenAiHost(uri.host)) {
      return null;
    }

    return {
      'type': enabled ? 'enabled' : 'disabled',
    };
  }

  String _buildReasoningEffort(Uri uri, ReasoningEffort effort) {
    if (_isOfficialOpenAiHost(uri.host)) {
      return effort.apiValue;
    }

    return switch (effort) {
      ReasoningEffort.low || ReasoningEffort.medium || ReasoningEffort.high =>
        'high',
      ReasoningEffort.xhigh => 'max',
    };
  }

  bool _isOfficialOpenAiHost(String host) {
    final normalizedHost = host.toLowerCase();
    return normalizedHost == 'api.openai.com' ||
        normalizedHost.endsWith('.openai.com');
  }
}

class ChatCompletionException implements Exception {
  const ChatCompletionException(this.message);

  final String message;

  @override
  String toString() => message;
}

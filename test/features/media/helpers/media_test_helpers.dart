import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:oh_my_llm/core/http/custom_headers_http_client.dart';
export 'package:oh_my_llm/core/http/custom_headers_http_client.dart';
import 'package:oh_my_llm/core/http/http_client_provider.dart';
export 'package:oh_my_llm/core/http/http_client_provider.dart';
import 'package:oh_my_llm/features/media/application/media_browser_controller.dart';
export 'package:oh_my_llm/features/media/application/media_browser_controller.dart';
import 'package:oh_my_llm/features/media/domain/models/file_item.dart';
export 'package:oh_my_llm/features/media/domain/models/file_item.dart';
import 'package:oh_my_llm/features/media/domain/models/media_server_info.dart';
export 'package:oh_my_llm/features/media/domain/models/media_server_info.dart';

const testServer = MediaServerInfo(ip: '192.168.1.5', httpPort: 8080);

String fileListJson(List<FileItem> items) => jsonEncode(
      items.map((i) => i.toJson()).toList(),
    );

http.Client okMockClient(String body) =>
    MockClient((_) async => http.Response(body, 200));

http.Client statusMockClient(int status) =>
    MockClient((_) async => http.Response('{}', status));

http.Client throwingMockClient() =>
    MockClient((_) async => throw http.ClientException('网络错误'));

ProviderContainer createMediaTestContainer({required http.Client httpClient}) {
  final container = ProviderContainer(
    overrides: [
      httpClientProvider.overrideWithValue(
        CustomHeadersHttpClient(httpClient, {}),
      ),
    ],
  );
  container.read(mediaBrowserControllerProvider);
  return container;
}

/// 设置 server 并等待 loadDirectory('/') 完成。
///
/// [initWithServer] 是 void，内部 fire-and-forget 调用 loadDirectory。
/// 此函数轮询直到 isLoading 回到 false（表示请求完成）。
Future<void> initBrowserAndWait(ProviderContainer container) async {
  final controller = container.read(mediaBrowserControllerProvider.notifier);
  controller.initWithServer(testServer);
  for (int i = 0; i < 50; i++) {
    await Future<void>.delayed(Duration.zero);
    if (!container.read(mediaBrowserControllerProvider).isLoading) break;
  }
}

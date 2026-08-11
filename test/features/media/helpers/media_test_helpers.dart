import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:oh_my_llm/core/http/peer_http_client_provider.dart';
export 'package:oh_my_llm/core/http/peer_http_client_provider.dart';
import 'package:oh_my_llm/features/media/application/media_browser_controller.dart';
export 'package:oh_my_llm/features/media/application/media_browser_controller.dart';
import 'package:oh_my_llm/features/media/domain/models/file_item.dart';
export 'package:oh_my_llm/features/media/domain/models/file_item.dart';
import 'package:oh_my_llm/features/media/domain/models/media_server_info.dart';
export 'package:oh_my_llm/features/media/domain/models/media_server_info.dart';

const testServer = MediaServerInfo(ip: '192.168.1.5', httpPort: 8080);

/// 测试用 MediaBrowserController：不发起网络请求，直接返回注入的初始状态。
///
/// 可选 [itemsByPath] 让 [navigateTo] 按路径同步切换目录内容，
/// 只验证 MediaBrowserTab 的浏览链路；生产 navigateTo 的加载与历史
/// 语义由应用层测试覆盖。
class FakeMediaBrowserController extends MediaBrowserController {
  FakeMediaBrowserController(this.initialState, {this.itemsByPath = const {}});

  final MediaBrowserState initialState;
  final Map<String, List<FileItem>> itemsByPath;

  @override
  MediaBrowserState build() => initialState;

  @override
  Future<void> navigateTo(String path) async {
    state = state.copyWith(
      currentPath: path,
      items: itemsByPath[path] ?? const [],
      pathHistory: [...state.pathHistory, state.currentPath],
    );
  }
}

String fileListJson(List<FileItem> items) =>
    jsonEncode(items.map((i) => i.toJson()).toList());

http.Client okMockClient(String body) =>
    MockClient((_) async => http.Response(body, 200));

http.Client statusMockClient(int status) =>
    MockClient((_) async => http.Response('{}', status));

http.Client throwingMockClient() =>
    MockClient((_) async => throw http.ClientException('网络错误'));

ProviderContainer createMediaTestContainer({
  required http.Client httpClient,
  bool retainBrowserListener = true,
}) {
  final container = ProviderContainer(
    overrides: [peerHttpClientProvider.overrideWithValue(httpClient)],
  );
  if (retainBrowserListener) {
    final subscription = container.listen(
      mediaBrowserControllerProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
  } else {
    container.read(mediaBrowserControllerProvider);
  }
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
    await Future<void>.value();
    if (!container.read(mediaBrowserControllerProvider).isLoading) break;
  }
}

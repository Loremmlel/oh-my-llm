import 'dart:io';

import 'package:oh_my_llm/core/http/http_route_handler.dart';

/// 纯 HTTP 路由器封装。
///
/// 绑定到 OS 分配的随机端口，遍历注册的 [HttpRouteHandler] 列表
/// 进行请求分发。不包含任何业务逻辑。
///
/// 同步业务逻辑已提取至 [SyncHttpHandler]，媒体相关在 [MediaHttpHandler]。
class SyncHttpServer {
  HttpServer? _server;

  bool get isRunning => _server != null;

  /// 启动 HTTP 路由器，注册 [handlers] 并按 canHandle 分发请求。
  ///
  /// 返回分配的端口号。
  Future<int> start({required List<HttpRouteHandler> handlers}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);

    final server = _server!;

    server.listen((request) async {
      for (final handler in handlers) {
        if (handler.canHandle(request)) {
          await handler.handle(request);
          return;
        }
      }
      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
    });

    return server.port;
  }

  /// 停止服务端并关闭所有连接。
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}

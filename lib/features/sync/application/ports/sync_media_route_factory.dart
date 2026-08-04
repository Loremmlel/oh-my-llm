import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/http/http_route_handler.dart';

/// 创建随 Sync 服务端一同运行的媒体 HTTP 路由。
abstract interface class SyncMediaRouteFactory {
  Future<List<HttpRouteHandler>> createRoutes();
}

/// 必须由 app composition 或测试显式绑定的媒体路由工厂。
final syncMediaRouteFactoryProvider = Provider<SyncMediaRouteFactory>((ref) {
  throw StateError('SyncMediaRouteFactory 尚未由应用组合层绑定');
});

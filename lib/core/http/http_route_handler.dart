import 'dart:io';

/// HTTP 路由处理器接口。
///
/// 放在 core/http/ 而非 sync/data/ 是为了避免跨 feature data 层依赖：
///   - SyncHttpHandler（sync/data/）实现它
///   - MediaHttpHandler（media/data/）实现它
///
/// 两者平等依赖 core 层，不存在 sync → media 或 media → sync 的 data 层导入。
abstract class HttpRouteHandler {
  /// 是否能处理该请求。
  ///
  /// 实现应仅检查 method + path，不读取 body（body 是流式消费的）。
  bool canHandle(HttpRequest request);

  /// 处理请求。实现者负责写入响应并关闭 response。
  ///
  /// 仅在 [canHandle] 返回 true 时被调用。
  Future<void> handle(HttpRequest request);
}

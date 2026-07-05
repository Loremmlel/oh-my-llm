import 'dart:io';

import 'package:oh_my_llm/core/http/http_response_writer.dart';
import 'package:oh_my_llm/core/http/http_route_handler.dart';

import 'media_directory_scanner.dart';

/// 媒体 HTTP Handler 抽象基类。
///
/// 统一处理：
/// - [canHandle]：GET + [urlPrefix] 前缀匹配
/// - 路径提取与解码
/// - 三层异常处理（PathTraversalException / FileSystemException / 兜底）
///
/// 子类只需实现 [handleSafe]，在特定异常类型上覆写 [onUnhandledError]。
abstract class MediaHttpHandlerBase implements HttpRouteHandler {
  final String urlPrefix;
  final MediaDirectoryScanner scanner;

  MediaHttpHandlerBase({required this.urlPrefix, required this.scanner});

  @override
  bool canHandle(HttpRequest request) =>
      request.method == 'GET' && request.uri.path.startsWith(urlPrefix);

  /// 从请求 URI 中提取并解码相对路径。
  ///
  /// 子类可覆写以处理特殊 URL 模式（如精确匹配 + 前缀匹配混合）。
  String extractPath(HttpRequest request) {
    final raw = request.uri.path.substring(urlPrefix.length);
    if (raw.isEmpty || raw == '/') return '/';
    return Uri.decodeComponent(raw);
  }

  @override
  Future<void> handle(HttpRequest request) async {
    try {
      final relativePath = extractPath(request);
      await handleSafe(request, relativePath);
    } on PathTraversalException catch (e) {
      writeJsonError(
          request.response, HttpStatus.forbidden, '路径穿越被拒绝: $e');
    } on FileSystemException catch (e) {
      final status = e.osError?.errorCode == 2
          ? HttpStatus.notFound
          : HttpStatus.internalServerError;
      writeJsonError(request.response, status, '文件访问失败: ${e.message}');
    } catch (e) {
      if (await onUnhandledError(request, e)) return;
      writeJsonError(
          request.response, HttpStatus.internalServerError, '服务端错误: $e');
    }
  }

  /// 子类实现具体处理逻辑。
  ///
  /// [relativePath] 已解码，以 `/` 开头。
  /// 实现必须写入响应并关闭 [request.response]。
  Future<void> handleSafe(HttpRequest request, String relativePath);

  /// 处理基类 catch 块未识别的异常。
  ///
  /// 返回 true 表示已处理（基类不再写错误响应），否则返回 false。
  Future<bool> onUnhandledError(HttpRequest request, Object error) async =>
      false;
}

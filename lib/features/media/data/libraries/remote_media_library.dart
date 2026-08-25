import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:oh_my_llm/features/media/application/models/media_library_failure.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource_request.dart';
import 'package:oh_my_llm/features/media/application/ports/media_library.dart';
import 'package:oh_my_llm/features/media/data/http/dto/media_file_item_dto.dart';
import 'package:oh_my_llm/features/media/domain/media_file_classification.dart';
import 'package:oh_my_llm/features/media/domain/models/file_item.dart';
import 'package:oh_my_llm/features/media/domain/models/video_item.dart';

/// 面向局域网 peer 的 HTTP 媒体库适配器，服务端为本项目的
/// `/api/media/*` HTTP 处理器。
///
/// 构造时一次性校验 base URI；资源 URI 全部用 `pathSegments` 逐段编码，
/// 不手工拼接 authority。列表与递归扫描会发起请求，资产与缩略图只解析
/// URI、不做 HTTP 预检。本类不读取任何全局 Provider，httpClient 由调用方注入。
final class RemoteMediaLibrary implements MediaLibrary {
  RemoteMediaLibrary({
    required Uri baseUri,
    required http.Client httpClient,
    this.directoryTimeout = const Duration(seconds: 10),
    this.recursiveTimeout = const Duration(seconds: 15),
  }) : _baseUri = _validateBaseUri(baseUri),
       _httpClient = httpClient;

  final Uri _baseUri;
  final http.Client _httpClient;
  final Duration directoryTimeout;
  final Duration recursiveTimeout;

  @override
  Future<List<FileItem>> listDirectory(String relativePath) async {
    final response = await _get(
      _mediaUri(const ['list'], relativePath),
      directoryTimeout,
    );
    try {
      return MediaFileItemDto.listFromJson(response.body)
          .map((dto) => dto.toDomain())
          .toList();
    } on FormatException {
      throw const MediaLibraryFailure(
        MediaLibraryFailureCode.invalidResponse,
        '媒体服务响应失败',
      );
    } on TypeError {
      throw const MediaLibraryFailure(
        MediaLibraryFailureCode.invalidResponse,
        '媒体服务响应失败',
      );
    }
  }

  @override
  Future<List<VideoItem>> listVideosRecursively(String relativePath) async {
    final response = await _get(
      _mediaUri(const ['videos', 'recursive'], relativePath),
      recursiveTimeout,
    );
    try {
      final decoded = jsonDecode(response.body) as List<dynamic>;
      return decoded
          .map((e) => VideoItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on FormatException {
      throw const MediaLibraryFailure(
        MediaLibraryFailureCode.invalidResponse,
        '媒体服务响应失败',
      );
    } on TypeError {
      throw const MediaLibraryFailure(
        MediaLibraryFailureCode.invalidResponse,
        '媒体服务响应失败',
      );
    }
  }

  @override
  Future<MediaResource?> resolveThumbnail(MediaThumbnailRequest request) async {
    if (!request.hasThumbnail) return null;
    return NetworkMediaResource(
      _mediaUri(const ['thumbnail'], request.relativePath),
    );
  }

  @override
  Future<MediaResource> resolveAsset(MediaAssetRequest request) async {
    final supported = switch (request.kind) {
      MediaAssetKind.image => isImageFile(request.relativePath),
      MediaAssetKind.video => isVideoFile(request.relativePath),
    };
    if (!supported) {
      throw const MediaLibraryFailure(
        MediaLibraryFailureCode.unsupportedMedia,
        '不支持的媒体类型',
      );
    }
    final route = request.kind == MediaAssetKind.image ? 'image' : 'video';
    return NetworkMediaResource(_mediaUri([route], request.relativePath));
  }

  /// 拼接 `/api/media/<routeSegments>/<relativePath>`。
  ///
  /// [routeSegments] 是端点的分段（如递归扫描为 `['videos', 'recursive']`），
  /// 与 [relativePath] 一起交给 `pathSegments` 逐段编码，保证中文路径正确转义。
  Uri _mediaUri(List<String> routeSegments, String relativePath) {
    final segments = _relativeSegments(relativePath);
    return _baseUri.replace(
      pathSegments: ['api', 'media', ...routeSegments, ...segments],
      query: null,
      fragment: null,
    );
  }

  /// 统一 GET：先按状态码映射失败，再交回调用方解码正文。
  Future<http.Response> _get(Uri uri, Duration timeout) async {
    try {
      final response = await _httpClient.get(uri).timeout(timeout);
      if (response.statusCode == 200) return response;
      throw switch (response.statusCode) {
        400 || 403 => const MediaLibraryFailure(
          MediaLibraryFailureCode.invalidPath,
          '媒体路径无效',
        ),
        404 => const MediaLibraryFailure(
          MediaLibraryFailureCode.notFound,
          '媒体资源不存在',
        ),
        408 || 504 => const MediaLibraryFailure(
          MediaLibraryFailureCode.timeout,
          '媒体请求超时',
        ),
        _ => const MediaLibraryFailure(
          MediaLibraryFailureCode.invalidResponse,
          '媒体服务响应失败',
        ),
      };
    } on TimeoutException {
      throw const MediaLibraryFailure(
        MediaLibraryFailureCode.timeout,
        '媒体请求超时',
      );
    } on http.ClientException {
      throw const MediaLibraryFailure(
        MediaLibraryFailureCode.networkUnavailable,
        '无法连接媒体服务',
      );
    }
  }

  /// 校验 base URI：HTTP(S)、非空 host、无 userInfo/query/fragment、
  /// path 为空或 `/`。
  static Uri _validateBaseUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw ArgumentError.value(uri, 'baseUri', '必须是 HTTP(S) 的 base URI');
    }
    if (uri.host.isEmpty) {
      throw ArgumentError.value(uri, 'baseUri', 'host 不能为空');
    }
    if (uri.userInfo.isNotEmpty) {
      throw ArgumentError.value(uri, 'baseUri', '不得包含 userInfo');
    }
    if (uri.hasQuery) {
      throw ArgumentError.value(uri, 'baseUri', '不得包含 query');
    }
    if (uri.hasFragment) {
      throw ArgumentError.value(uri, 'baseUri', '不得包含 fragment');
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      throw ArgumentError.value(uri, 'baseUri', 'path 必须为空或 /');
    }
    return uri;
  }

  /// 校验相对路径并切分为待编码段：要求前导 `/`，拒绝空路径与 `.`/`..` 段；
  /// 根 `/` 返回空列表。
  static List<String> _relativeSegments(String relativePath) {
    if (relativePath == '/') return const [];
    if (relativePath.isEmpty || !relativePath.startsWith('/')) {
      throw const MediaLibraryFailure(
        MediaLibraryFailureCode.invalidPath,
        '媒体路径无效',
      );
    }
    final segments = relativePath
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty || segments.any((s) => s == '.' || s == '..')) {
      throw const MediaLibraryFailure(
        MediaLibraryFailureCode.invalidPath,
        '媒体路径无效',
      );
    }
    return segments;
  }
}

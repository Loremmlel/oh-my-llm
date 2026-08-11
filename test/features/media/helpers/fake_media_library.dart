import 'dart:async';

import 'package:oh_my_llm/features/media/application/models/media_library_failure.dart';
import 'package:oh_my_llm/features/media/application/models/media_library_source.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource_request.dart';
import 'package:oh_my_llm/features/media/application/ports/media_library.dart';
import 'package:oh_my_llm/features/media/application/ports/media_library_factory.dart';
import 'package:oh_my_llm/features/media/domain/models/file_item.dart';
import 'package:oh_my_llm/features/media/domain/models/video_item.dart';

/// 受控的媒体库 Fake：调用先记录，再按 失败 -> Completer -> 配置结果 的
/// 确定性顺序决定行为，供后续任务的所有测试复用。
final class FakeMediaLibrary implements MediaLibrary {
  final Map<String, List<FileItem>> directoryResults = {};
  final Map<String, List<VideoItem>> recursiveVideoResults = {};
  final Map<MediaAssetRequest, MediaResource> assetResults = {};
  final Map<MediaThumbnailRequest, MediaResource?> thumbnailResults = {};
  final List<String> listDirectoryCalls = [];
  final List<String> listVideosRecursivelyCalls = [];
  final List<MediaAssetRequest> resolveAssetCalls = [];
  final List<MediaThumbnailRequest> resolveThumbnailCalls = [];
  Completer<List<FileItem>>? pendingDirectory;
  Completer<List<VideoItem>>? pendingVideos;
  MediaLibraryFailure? directoryFailure;
  MediaLibraryFailure? videoFailure;
  MediaLibraryFailure? assetFailure;
  MediaLibraryFailure? thumbnailFailure;

  @override
  Future<List<FileItem>> listDirectory(String relativePath) async {
    listDirectoryCalls.add(relativePath);
    final failure = directoryFailure;
    if (failure != null) {
      throw failure;
    }
    final pending = pendingDirectory;
    if (pending != null) {
      return pending.future;
    }
    return directoryResults[relativePath] ?? const [];
  }

  @override
  Future<List<VideoItem>> listVideosRecursively(String relativePath) async {
    listVideosRecursivelyCalls.add(relativePath);
    final failure = videoFailure;
    if (failure != null) {
      throw failure;
    }
    final pending = pendingVideos;
    if (pending != null) {
      return pending.future;
    }
    return recursiveVideoResults[relativePath] ?? const [];
  }

  @override
  Future<MediaResource?> resolveThumbnail(MediaThumbnailRequest request) async {
    resolveThumbnailCalls.add(request);
    final failure = thumbnailFailure;
    if (failure != null) {
      throw failure;
    }
    // 返回配置结果或 null（缩略图本就允许缺失）。
    return thumbnailResults[request];
  }

  @override
  Future<MediaResource> resolveAsset(MediaAssetRequest request) async {
    resolveAssetCalls.add(request);
    final failure = assetFailure;
    if (failure != null) {
      throw failure;
    }
    // 资产返回非空；未配置时显式失败，避免测试静默拿到错误结果。
    final resource = assetResults[request];
    if (resource == null) {
      throw StateError('未配置 $request 的资产解析结果');
    }
    return resource;
  }
}

/// 受控的媒体库工厂 Fake：记录打开的来源，按 失败 -> Completer -> 固定库 顺序返回。
final class FakeMediaLibraryFactory implements MediaLibraryFactory {
  FakeMediaLibraryFactory(this.library);
  final MediaLibrary library;
  final List<MediaLibrarySource> openedSources = [];
  Completer<MediaLibrary>? pendingOpen;
  MediaLibraryFailure? failure;

  @override
  Future<MediaLibrary> open(MediaLibrarySource source) async {
    openedSources.add(source);
    final f = failure;
    if (f != null) {
      throw f;
    }
    final pending = pendingOpen;
    if (pending != null) {
      return pending.future;
    }
    return library;
  }
}

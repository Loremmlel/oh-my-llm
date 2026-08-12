/// 懒资源解析：按当前会话库分派资产/缩略图请求。
///
/// 依赖 [mediaLibrarySessionProvider]，会话状态变化时自动重新解析；
/// 库失败原样抛出，不在此处字符串化，由调用方按 [MediaLibraryFailure] 呈现。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'media_library_session_controller.dart';
import 'models/media_library_failure.dart';
import 'models/media_resource.dart';
import 'models/media_resource_request.dart';

final mediaResourceProvider = FutureProvider.autoDispose
    .family<MediaResource?, MediaResourceRequest>((ref, request) async {
      final session = ref.watch(mediaLibrarySessionProvider);
      if (session case MediaLibrarySessionFailed(:final failure)) throw failure;
      if (session is! MediaLibrarySessionActive) {
        throw const MediaLibraryFailure(
          MediaLibraryFailureCode.sourceUnavailable,
          '媒体会话不可用',
        );
      }
      return switch (request) {
        MediaAssetRequest() => session.library.resolveAsset(request),
        MediaThumbnailRequest() => session.library.resolveThumbnail(request),
      };
    });

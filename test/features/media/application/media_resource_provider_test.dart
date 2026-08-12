import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/application/media_library_session_controller.dart';
import 'package:oh_my_llm/features/media/application/media_resource_provider.dart';
import 'package:oh_my_llm/features/media/application/models/media_library_failure.dart';
import 'package:oh_my_llm/features/media/application/models/media_library_source.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource_request.dart';
import 'package:oh_my_llm/features/media/application/ports/media_library.dart';
import 'package:oh_my_llm/features/media/application/ports/media_library_factory.dart';
import 'package:oh_my_llm/features/media/domain/models/file_item.dart';
import 'package:oh_my_llm/features/media/domain/models/video_item.dart';

import '../helpers/fake_media_library.dart';

const _assetRequest = MediaAssetRequest(
  kind: MediaAssetKind.video,
  relativePath: '/a.mp4',
);
const _thumbnailRequest = MediaThumbnailRequest(
  relativePath: '/a.mp4',
  sizeBytes: 1024,
  lastModified: 1234,
  hasThumbnail: true,
);

/// 资产解析受控的媒体库 Fake：resolveAsset 返回挂起的 Completer，
/// 未涉及的库方法显式失败，避免测试静默走错路径。
final class _PendingAssetLibrary implements MediaLibrary {
  final Completer<MediaResource> pendingAsset = Completer<MediaResource>();
  final List<MediaAssetRequest> resolveAssetCalls = [];

  @override
  Future<MediaResource> resolveAsset(MediaAssetRequest request) {
    resolveAssetCalls.add(request);
    return pendingAsset.future;
  }

  @override
  Future<List<FileItem>> listDirectory(String relativePath) =>
      throw UnimplementedError();

  @override
  Future<List<VideoItem>> listVideosRecursively(String relativePath) =>
      throw UnimplementedError();

  @override
  Future<MediaResource?> resolveThumbnail(MediaThumbnailRequest request) =>
      throw UnimplementedError();
}

/// 按打开次序返回不同库的工厂 Fake：用于验证会话替换切到新库。
///
/// 共享的 [FakeMediaLibraryFactory] 固定返回单一库，无法表达「激活 A 后
/// 再激活 B 拿到新库」，故此处按调用序依次吐出给定库列表。
final class _SwitchingMediaLibraryFactory implements MediaLibraryFactory {
  _SwitchingMediaLibraryFactory(this._openResults);
  final List<MediaLibrary> _openResults;
  int _nextIndex = 0;

  @override
  Future<MediaLibrary> open(MediaLibrarySource source) {
    final result = _openResults[_nextIndex.clamp(0, _openResults.length - 1)];
    _nextIndex++;
    return Future.value(result);
  }
}

/// 读取资源 future 并保持对应 autoDispose 元素存活。
///
/// `mediaResourceProvider` 是 autoDispose family：若只有 `container.read`
/// 而没有监听器，元素会在异步体完成前被回收（Riverpod 对 loading 态 dispose
/// 会以 StateError 收尾）。监听器在等待期间持有元素，避免与回收竞争。
Future<MediaResource?> readResource(
  ProviderContainer container,
  MediaResourceRequest request,
) async {
  final sub = container.listen(mediaResourceProvider(request), (_, _) {});
  try {
    return await container.read(mediaResourceProvider(request).future);
  } finally {
    sub.close();
  }
}

/// 构建禁用自动重试的测试容器。
///
/// 本文件验证媒体资源分派与失败契约，不验证 Riverpod 的退避策略；保留默认
/// 重试会让 `.future` 的预期失败断言等待全部指数退避结束。
ProviderContainer _createContainer(MediaLibraryFactory factory) {
  return ProviderContainer.test(
    overrides: [mediaLibraryFactoryProvider.overrideWithValue(factory)],
    retry: (_, _) => null,
  );
}

void main() {
  test('未激活或打开中的会话返回 sourceUnavailable', () async {
    final library = FakeMediaLibrary();
    final factory = FakeMediaLibraryFactory(library)
      ..pendingOpen = Completer<MediaLibrary>();
    final container = _createContainer(factory);

    // 初始 Inactive：资源解析直接失败。
    await expectLater(
      readResource(container, _assetRequest),
      throwsA(
        isA<MediaLibraryFailure>().having(
          (f) => f.code,
          'code',
          MediaLibraryFailureCode.sourceUnavailable,
        ),
      ),
    );

    // Opening：同样失败。
    final sub = container.listen(mediaLibrarySessionProvider, (_, _) {});
    addTearDown(sub.close);
    final activation = container
        .read(mediaLibrarySessionProvider.notifier)
        .activate(const LocalMediaLibrarySource(r'D:\Media'));
    await expectLater(
      readResource(container, _assetRequest),
      throwsA(
        isA<MediaLibraryFailure>().having(
          (f) => f.code,
          'code',
          MediaLibraryFailureCode.sourceUnavailable,
        ),
      ),
    );

    factory.pendingOpen!.complete(library);
    await activation;
  });

  test('失败的会话原样抛出其 MediaLibraryFailure', () async {
    const failure = MediaLibraryFailure(
      MediaLibraryFailureCode.networkUnavailable,
      '对端不可达',
    );
    final library = FakeMediaLibrary();
    final factory = FakeMediaLibraryFactory(library);
    final container = _createContainer(factory);
    final sub = container.listen(mediaLibrarySessionProvider, (_, _) {});
    addTearDown(sub.close);

    container.read(mediaLibrarySessionProvider.notifier).fail(failure);
    await expectLater(
      readResource(container, _assetRequest),
      throwsA(
        isA<MediaLibraryFailure>().having((f) => f.message, 'message', '对端不可达'),
      ),
    );
  });

  test('资产请求只调用一次 resolveAsset', () async {
    final resource = NetworkMediaResource(
      Uri.parse('http://192.168.1.5:8080/api/media/video/a.mp4'),
    );
    final library = FakeMediaLibrary()..assetResults[_assetRequest] = resource;
    final factory = FakeMediaLibraryFactory(library);
    final container = _createContainer(factory);
    final sub = container.listen(mediaLibrarySessionProvider, (_, _) {});
    addTearDown(sub.close);

    await container
        .read(mediaLibrarySessionProvider.notifier)
        .activate(const LocalMediaLibrarySource(r'D:\Media'));
    final result = await readResource(container, _assetRequest);
    expect(result, same(resource));
    expect(library.resolveAssetCalls, [_assetRequest]);
  });

  test('缩略图请求只调用一次 resolveThumbnail', () async {
    final resource = NetworkMediaResource(
      Uri.parse('http://192.168.1.5:8080/api/media/thumb/a.jpg'),
    );
    final library = FakeMediaLibrary()
      ..thumbnailResults[_thumbnailRequest] = resource;
    final factory = FakeMediaLibraryFactory(library);
    final container = _createContainer(factory);
    final sub = container.listen(mediaLibrarySessionProvider, (_, _) {});
    addTearDown(sub.close);

    await container
        .read(mediaLibrarySessionProvider.notifier)
        .activate(const LocalMediaLibrarySource(r'D:\Media'));
    final result = await readResource(container, _thumbnailRequest);
    expect(result, same(resource));
    expect(library.resolveThumbnailCalls, [_thumbnailRequest]);
  });

  test('会话重置/替换使挂起的 provider 结果失效，新读取使用新库', () async {
    final pending = _PendingAssetLibrary();
    final staleResource = NetworkMediaResource(
      Uri.parse('http://192.168.1.5:8080/api/media/video/stale.mp4'),
    );
    final freshResource = NetworkMediaResource(
      Uri.parse('http://192.168.1.5:8080/api/media/video/fresh.mp4'),
    );
    final fresh = FakeMediaLibrary()
      ..assetResults[_assetRequest] = freshResource;
    final factory = _SwitchingMediaLibraryFactory([pending, fresh]);
    final container = _createContainer(factory);
    final sub = container.listen(mediaLibrarySessionProvider, (_, _) {});
    addTearDown(sub.close);

    // 第一个会话激活后读取：资产解析挂起，监听器持有元素等待。
    await container
        .read(mediaLibrarySessionProvider.notifier)
        .activate(const LocalMediaLibrarySource(r'D:\Media\first'));
    final pendingSub = container.listen(
      mediaResourceProvider(_assetRequest),
      (_, _) {},
    );
    container.read(mediaResourceProvider(_assetRequest).future);
    expect(pending.resolveAssetCalls, hasLength(1));

    // 重置并替换为新库：旧挂起的 provider 结果被判定失效。
    container.read(mediaLibrarySessionProvider.notifier).reset();
    await container
        .read(mediaLibrarySessionProvider.notifier)
        .activate(const LocalMediaLibrarySource(r'D:\Media\second'));
    // 新读取使用新库，旧库不再被调用。
    final freshResult = await readResource(container, _assetRequest);
    expect(freshResult, same(freshResource));
    expect(fresh.resolveAssetCalls, hasLength(1));
    expect(pending.resolveAssetCalls, hasLength(1));

    // 旧挂起结果随后完成：不会覆盖当前会话的新库结果。
    pending.pendingAsset.complete(staleResource);
    await container.pump();
    final afterStale = await readResource(container, _assetRequest);
    expect(afterStale, same(freshResource));
    expect(fresh.resolveAssetCalls, hasLength(1));
    expect(pending.resolveAssetCalls, hasLength(1));
    pendingSub.close();
  });
}

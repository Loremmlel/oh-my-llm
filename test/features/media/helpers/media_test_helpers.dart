import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/application/media_browser_controller.dart';
export 'package:oh_my_llm/features/media/application/media_browser_controller.dart';
import 'package:oh_my_llm/features/media/application/media_library_session_controller.dart';
import 'package:oh_my_llm/features/media/application/models/media_library_source.dart';
import 'package:oh_my_llm/features/media/application/ports/media_library.dart';
import 'package:oh_my_llm/features/media/application/ports/media_library_factory.dart';
import 'package:oh_my_llm/features/media/application/shuffle_playback_controller.dart';
export 'package:oh_my_llm/features/media/application/shuffle_playback_controller.dart';
import 'package:oh_my_llm/features/media/domain/models/file_item.dart';
export 'package:oh_my_llm/features/media/domain/models/file_item.dart';

import 'fake_media_library.dart';

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

/// 预激活媒体会话的测试替身：build 即返回 Active。
///
/// widget 测试经 `mediaLibrarySessionProvider.overrideWith` 注入，
/// 免去真实激活的异步时序，从首帧起会话即可用。
final class PreActivatedMediaLibrarySessionController
    extends MediaLibrarySessionController {
  PreActivatedMediaLibrarySessionController(
    this.library, {
    this.generation = 1,
  });

  final MediaLibrary library;
  final int generation;

  @override
  MediaLibrarySessionState build() => MediaLibrarySessionActive(
    sourceKind: MediaSourceKind.remote,
    library: library,
    generation: generation,
  );
}

/// 应用层测试容器：注入 Fake 媒体库工厂并持有全部 autoDispose 控制器的订阅。
///
/// 会话/浏览器/随机播放三个 autoDispose 控制器由本 helper 统一订阅保活，
/// 并在 tearDown 释放；单个测试不得再为这些控制器注册重复释放。
ProviderContainer createMediaLibraryTestContainer(FakeMediaLibrary library) {
  final container = ProviderContainer(
    overrides: [
      mediaLibraryFactoryProvider.overrideWithValue(
        FakeMediaLibraryFactory(library),
      ),
    ],
  );
  final sessionSubscription = container.listen(
    mediaLibrarySessionProvider,
    (_, _) {},
  );
  final browserSubscription = container.listen(
    mediaBrowserControllerProvider,
    (_, _) {},
  );
  final shuffleSubscription = container.listen(
    shufflePlaybackControllerProvider,
    (_, _) {},
  );
  addTearDown(() {
    sessionSubscription.close();
    browserSubscription.close();
    shuffleSubscription.close();
    container.dispose();
  });
  return container;
}

/// 与 [createMediaLibraryTestContainer] 相同，但接受任意 [MediaLibrary]，
/// 供需要自定义失败行为（如未知异常）的测试使用。
ProviderContainer createMediaLibraryTestContainerWith(MediaLibrary library) {
  final container = ProviderContainer(
    overrides: [
      mediaLibraryFactoryProvider.overrideWithValue(
        FakeMediaLibraryFactory(library),
      ),
    ],
  );
  final sessionSubscription = container.listen(
    mediaLibrarySessionProvider,
    (_, _) {},
  );
  final browserSubscription = container.listen(
    mediaBrowserControllerProvider,
    (_, _) {},
  );
  final shuffleSubscription = container.listen(
    shufflePlaybackControllerProvider,
    (_, _) {},
  );
  addTearDown(() {
    sessionSubscription.close();
    browserSubscription.close();
    shuffleSubscription.close();
    container.dispose();
  });
  return container;
}

/// 激活远端媒体会话（192.168.1.5:8080），并断言会话进入 Active。
Future<void> activateTestMediaSession(ProviderContainer container) async {
  final activated = await container
      .read(mediaLibrarySessionProvider.notifier)
      .activate(RemoteMediaLibrarySource(Uri.parse('http://192.168.1.5:8080')));
  expect(activated, isTrue);
  expect(
    container.read(mediaLibrarySessionProvider),
    isA<MediaLibrarySessionActive>(),
  );
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/application/media_library_session_controller.dart';
import 'package:oh_my_llm/features/media/application/models/media_library_failure.dart';
import 'package:oh_my_llm/features/media/application/models/media_library_source.dart';
import 'package:oh_my_llm/features/media/application/ports/media_library.dart';
import 'package:oh_my_llm/features/media/application/ports/media_library_factory.dart';

import '../helpers/fake_media_library.dart';

/// 工厂 Fake：open 抛出未知异常，用于验证非 MediaLibraryFailure 的映射。
final class _ExplodingMediaLibraryFactory implements MediaLibraryFactory {
  @override
  Future<MediaLibrary> open(MediaLibrarySource source) async {
    throw StateError('内部实现细节：磁盘格式错误');
  }
}

void main() {
  test('reset 使挂起的 activate 结果过期', () async {
    final library = FakeMediaLibrary();
    final factory = FakeMediaLibraryFactory(library)
      ..pendingOpen = Completer<MediaLibrary>();
    final container = ProviderContainer(
      overrides: [mediaLibraryFactoryProvider.overrideWithValue(factory)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(mediaLibrarySessionProvider, (_, _) {});
    addTearDown(sub.close);

    final activation = container
        .read(mediaLibrarySessionProvider.notifier)
        .activate(const LocalMediaLibrarySource(r'D:\Media'));
    expect(
      container.read(mediaLibrarySessionProvider),
      isA<MediaLibrarySessionOpening>(),
    );
    container.read(mediaLibrarySessionProvider.notifier).reset();
    factory.pendingOpen!.complete(library);
    expect(await activation, isFalse);
    expect(
      container.read(mediaLibrarySessionProvider),
      isA<MediaLibrarySessionInactive>(),
    );
  });

  test('成功的激活返回 true 并保存来源类型/库/代数', () async {
    final library = FakeMediaLibrary();
    final factory = FakeMediaLibraryFactory(library);
    final container = ProviderContainer(
      overrides: [mediaLibraryFactoryProvider.overrideWithValue(factory)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(mediaLibrarySessionProvider, (_, _) {});
    addTearDown(sub.close);

    final result = await container
        .read(mediaLibrarySessionProvider.notifier)
        .activate(const LocalMediaLibrarySource(r'D:\Media'));
    expect(result, isTrue);
    final state = container.read(mediaLibrarySessionProvider);
    expect(state, isA<MediaLibrarySessionActive>());
    final active = state as MediaLibrarySessionActive;
    expect(active.sourceKind, MediaSourceKind.local);
    expect(active.library, same(library));
    expect(active.generation, 1);
  });

  test('较新的 activate 优先于旧的挂起 activate', () async {
    final first = FakeMediaLibrary();
    final second = FakeMediaLibrary();
    final factory = FakeMediaLibraryFactory(first);
    final container = ProviderContainer(
      overrides: [mediaLibraryFactoryProvider.overrideWithValue(factory)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(mediaLibrarySessionProvider, (_, _) {});
    addTearDown(sub.close);

    final firstCompleter = Completer<MediaLibrary>();
    factory.pendingOpen = firstCompleter;
    final firstActivation = container
        .read(mediaLibrarySessionProvider.notifier)
        .activate(const LocalMediaLibrarySource(r'D:\Media\first'));

    final secondCompleter = Completer<MediaLibrary>();
    factory.pendingOpen = secondCompleter;
    final secondActivation = container
        .read(mediaLibrarySessionProvider.notifier)
        .activate(const LocalMediaLibrarySource(r'D:\Media\second'));

    // 较新的激活先完成：成为当前会话。
    secondCompleter.complete(second);
    expect(await secondActivation, isTrue);
    final newerState = container.read(mediaLibrarySessionProvider);
    expect(newerState, isA<MediaLibrarySessionActive>());
    final newerActive = newerState as MediaLibrarySessionActive;
    expect(newerActive.library, same(second));
    expect(newerActive.generation, 2);

    // 旧的挂起随后完成：结果被判定过期，不覆盖当前会话。
    firstCompleter.complete(first);
    expect(await firstActivation, isFalse);
    final finalState = container.read(mediaLibrarySessionProvider);
    expect(finalState, isA<MediaLibrarySessionActive>());
    expect((finalState as MediaLibrarySessionActive).library, same(second));
  });

  test('工厂 MediaLibraryFailure 产生携带相同失败信息的 Failed', () async {
    const failure = MediaLibraryFailure(
      MediaLibraryFailureCode.accessDenied,
      '拒绝访问',
    );
    final library = FakeMediaLibrary();
    final factory = FakeMediaLibraryFactory(library)..failure = failure;
    final container = ProviderContainer(
      overrides: [mediaLibraryFactoryProvider.overrideWithValue(factory)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(mediaLibrarySessionProvider, (_, _) {});
    addTearDown(sub.close);

    final result = await container
        .read(mediaLibrarySessionProvider.notifier)
        .activate(const LocalMediaLibrarySource(r'D:\Media'));
    expect(result, isFalse);
    final state = container.read(mediaLibrarySessionProvider);
    expect(state, isA<MediaLibrarySessionFailed>());
    final failed = state as MediaLibrarySessionFailed;
    expect(failed.failure, same(failure));
    expect(failed.generation, 1);
  });

  test('未知工厂异常映射为 sourceUnavailable 且不包含异常文本', () async {
    final container = ProviderContainer(
      overrides: [
        mediaLibraryFactoryProvider.overrideWithValue(
          _ExplodingMediaLibraryFactory(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(mediaLibrarySessionProvider, (_, _) {});
    addTearDown(sub.close);

    final result = await container
        .read(mediaLibrarySessionProvider.notifier)
        .activate(const LocalMediaLibrarySource(r'D:\Media'));
    expect(result, isFalse);
    final state = container.read(mediaLibrarySessionProvider);
    expect(state, isA<MediaLibrarySessionFailed>());
    final failed = state as MediaLibrarySessionFailed;
    expect(failed.failure.code, MediaLibraryFailureCode.sourceUnavailable);
    expect(failed.failure.message, isNot(contains('磁盘格式错误')));
    expect(failed.failure.message, '媒体来源不可用');
  });

  test('fail 递增代数并发布 Failed', () async {
    final library = FakeMediaLibrary();
    final factory = FakeMediaLibraryFactory(library);
    final container = ProviderContainer(
      overrides: [mediaLibraryFactoryProvider.overrideWithValue(factory)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(mediaLibrarySessionProvider, (_, _) {});
    addTearDown(sub.close);

    await container
        .read(mediaLibrarySessionProvider.notifier)
        .activate(const LocalMediaLibrarySource(r'D:\Media'));
    final activatedState = container.read(mediaLibrarySessionProvider);
    final active = activatedState as MediaLibrarySessionActive;
    expect(active.generation, 1);

    const failure = MediaLibraryFailure(
      MediaLibraryFailureCode.notFound,
      '文件不存在',
    );
    container.read(mediaLibrarySessionProvider.notifier).fail(failure);
    final state = container.read(mediaLibrarySessionProvider);
    expect(state, isA<MediaLibrarySessionFailed>());
    final failed = state as MediaLibrarySessionFailed;
    expect(failed.generation, greaterThan(active.generation));
    expect(failed.failure, same(failure));
  });

  test('释放最后一个监听器并重建得到 Inactive', () async {
    final library = FakeMediaLibrary();
    final factory = FakeMediaLibraryFactory(library);
    final container = ProviderContainer(
      overrides: [mediaLibraryFactoryProvider.overrideWithValue(factory)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(mediaLibrarySessionProvider, (_, _) {});

    await container
        .read(mediaLibrarySessionProvider.notifier)
        .activate(const LocalMediaLibrarySource(r'D:\Media'));
    expect(
      container.read(mediaLibrarySessionProvider),
      isA<MediaLibrarySessionActive>(),
    );

    sub.close();
    await container.pump();
    expect(container.exists(mediaLibrarySessionProvider), isFalse);
    expect(
      container.read(mediaLibrarySessionProvider),
      isA<MediaLibrarySessionInactive>(),
    );
  });
}

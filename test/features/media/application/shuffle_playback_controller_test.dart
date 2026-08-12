import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/application/ports/media_library_factory.dart';
import 'package:oh_my_llm/features/media/application/shuffle_playback_controller.dart';
import 'package:oh_my_llm/features/media/domain/models/video_item.dart';

import '../helpers/fake_media_library.dart';
import '../helpers/media_test_helpers.dart';

void main() {
  group('ShufflePlaybackState', () {
    test('ShufflePlaybackActive 派生属性矩阵：首项/末项/单项列表', () {
      for (final (
            :name,
            :playlist,
            :index,
            :expectedIsFirst,
            :expectedIsLast,
            :expectedDisplayNumber,
            :expectedTotalCount,
          )
          in [
            (
              name: '首项',
              playlist: const [
                VideoItem(name: 'a.mp4', relativePath: '/a.mp4'),
                VideoItem(name: 'b.mp4', relativePath: '/sub/b.mp4'),
              ],
              index: 0,
              expectedIsFirst: true,
              expectedIsLast: false,
              expectedDisplayNumber: 1,
              expectedTotalCount: 2,
            ),
            (
              name: '末项',
              playlist: const [
                VideoItem(name: 'a.mp4', relativePath: '/a.mp4'),
                VideoItem(name: 'b.mp4', relativePath: '/sub/b.mp4'),
              ],
              index: 1,
              expectedIsFirst: false,
              expectedIsLast: true,
              expectedDisplayNumber: 2,
              expectedTotalCount: 2,
            ),
            (
              name: '单项列表首尾同为 true',
              playlist: const [
                VideoItem(name: 'only.mp4', relativePath: '/only.mp4'),
              ],
              index: 0,
              expectedIsFirst: true,
              expectedIsLast: true,
              expectedDisplayNumber: 1,
              expectedTotalCount: 1,
            ),
          ]) {
        final state = ShufflePlaybackActive(
          playlist: playlist,
          currentIndex: index,
          directoryPath: '/videos',
        );
        expect(state.isFirst, expectedIsFirst, reason: 'case: $name');
        expect(state.isLast, expectedIsLast, reason: 'case: $name');
        expect(
          state.displayNumber,
          expectedDisplayNumber,
          reason: 'case: $name',
        );
        expect(state.totalCount, expectedTotalCount, reason: 'case: $name');
        expect(state.currentVideo, playlist[index], reason: 'case: $name');
      }
    });
  });

  test('随机播放页面会话在观察者释放后重建为 Idle', () async {
    final container = ProviderContainer(
      overrides: [
        mediaLibraryFactoryProvider.overrideWithValue(
          FakeMediaLibraryFactory(FakeMediaLibrary()),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      shufflePlaybackControllerProvider,
      (_, _) {},
    );
    container.read(shufflePlaybackControllerProvider.notifier).reset();

    subscription.close();
    await container.pump();

    expect(container.exists(shufflePlaybackControllerProvider), isFalse);
    expect(
      container.read(shufflePlaybackControllerProvider),
      const ShufflePlaybackIdle(),
    );
  });
}

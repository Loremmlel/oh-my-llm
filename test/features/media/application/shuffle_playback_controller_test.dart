import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/media/application/shuffle_playback_controller.dart';
import 'package:oh_my_llm/features/media/data/media_directory_scanner.dart';

void main() {
  group('ShufflePlaybackState', () {
    final samplePlaylist = [
      const VideoItem(name: 'a.mp4', relativePath: '/a.mp4'),
      const VideoItem(name: 'b.mp4', relativePath: '/sub/b.mp4'),
    ];

    test('ShufflePlaybackActive 首项属性', () {
      final state = ShufflePlaybackActive(
        playlist: samplePlaylist,
        currentIndex: 0,
        directoryPath: '/videos',
      );
      expect(state.isFirst, isTrue);
      expect(state.isLast, isFalse);
      expect(state.displayNumber, 1);
      expect(state.totalCount, 2);
      expect(state.currentVideo, equals(samplePlaylist[0]));
    });

    test('快照播放列表且所有状态按值比较', () {
      final playlist = <VideoItem>[
        const VideoItem(name: 'test.mp4', relativePath: '/test.mp4'),
      ];
      final active = ShufflePlaybackActive(
        playlist: playlist,
        currentIndex: 0,
        directoryPath: '/',
      );
      playlist.clear();

      expect(active.playlist, hasLength(1));
      expect(() => active.playlist.clear(), throwsUnsupportedError);
      expect(const ShufflePlaybackIdle(), const ShufflePlaybackIdle());
      expect(const ShufflePlaybackLoading(), const ShufflePlaybackLoading());
      expect(
        active,
        ShufflePlaybackActive(
          playlist: const [
            VideoItem(name: 'test.mp4', relativePath: '/test.mp4'),
          ],
          currentIndex: 0,
          directoryPath: '/',
        ),
      );
    });

    test('ShufflePlaybackActive 末项属性', () {
      final state = ShufflePlaybackActive(
        playlist: samplePlaylist,
        currentIndex: 1,
        directoryPath: '/videos',
      );
      expect(state.isLast, isTrue);
      expect(state.isFirst, isFalse);
      expect(state.displayNumber, 2);
    });

    test('ShufflePlaybackActive 单项列表：首尾同为 true', () {
      final singlePlaylist = [
        const VideoItem(name: 'only.mp4', relativePath: '/only.mp4'),
      ];
      final state = ShufflePlaybackActive(
        playlist: singlePlaylist,
        currentIndex: 0,
        directoryPath: '/videos',
      );
      expect(state.isFirst, isTrue);
      expect(state.isLast, isTrue);
      expect(state.totalCount, 1);
    });
  });
}

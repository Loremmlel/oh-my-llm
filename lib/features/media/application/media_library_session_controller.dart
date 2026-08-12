/// 活动媒体会话状态机：由 [MediaLibraryFactory] 按来源打开的具体库承载。
///
/// 会话以 autoDispose 托管，页面离开后重建为 Inactive；代数（generation）
/// 单调递增，用于判定过期异步结果——旧会话的打开完成不得覆盖新会话。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/media_library_failure.dart';
import 'models/media_library_source.dart';
import 'ports/media_library.dart';
import 'ports/media_library_factory.dart';

sealed class MediaLibrarySessionState {
  const MediaLibrarySessionState();
}

final class MediaLibrarySessionInactive extends MediaLibrarySessionState {
  const MediaLibrarySessionInactive();
}

final class MediaLibrarySessionOpening extends MediaLibrarySessionState {
  const MediaLibrarySessionOpening(this.generation);
  final int generation;
}

final class MediaLibrarySessionActive extends MediaLibrarySessionState {
  const MediaLibrarySessionActive({
    required this.sourceKind,
    required this.library,
    required this.generation,
  });
  final MediaSourceKind sourceKind;
  final MediaLibrary library;
  final int generation;
}

final class MediaLibrarySessionFailed extends MediaLibrarySessionState {
  const MediaLibrarySessionFailed(this.generation, this.failure);
  final int generation;
  final MediaLibraryFailure failure;
}

final mediaLibrarySessionProvider =
    NotifierProvider<MediaLibrarySessionController, MediaLibrarySessionState>(
      MediaLibrarySessionController.new,
      isAutoDispose: true,
    );

class MediaLibrarySessionController extends Notifier<MediaLibrarySessionState> {
  int _generation = 0;

  @override
  MediaLibrarySessionState build() => const MediaLibrarySessionInactive();

  Future<bool> activate(MediaLibrarySource source) async {
    final generation = ++_generation;
    state = MediaLibrarySessionOpening(generation);
    try {
      final library = await ref.read(mediaLibraryFactoryProvider).open(source);
      if (!_isCurrent(generation)) return false;
      state = MediaLibrarySessionActive(
        sourceKind: source.kind,
        library: library,
        generation: generation,
      );
      return true;
    } on MediaLibraryFailure catch (failure) {
      if (_isCurrent(generation)) {
        state = MediaLibrarySessionFailed(generation, failure);
      }
      return false;
    } catch (_) {
      if (_isCurrent(generation)) {
        state = MediaLibrarySessionFailed(
          generation,
          const MediaLibraryFailure(
            MediaLibraryFailureCode.sourceUnavailable,
            '媒体来源不可用',
          ),
        );
      }
      return false;
    }
  }

  void fail(MediaLibraryFailure failure) {
    final generation = ++_generation;
    state = MediaLibrarySessionFailed(generation, failure);
  }

  void reset() {
    _generation++;
    state = const MediaLibrarySessionInactive();
  }

  bool _isCurrent(int generation) => ref.mounted && generation == _generation;
}

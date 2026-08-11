/// 媒体库工厂端口：按来源打开具体媒体库实例。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/features/media/application/models/media_library_source.dart';
import 'package:oh_my_llm/features/media/application/ports/media_library.dart';

abstract interface class MediaLibraryFactory {
  Future<MediaLibrary> open(MediaLibrarySource source);
}

final mediaLibraryFactoryProvider = Provider<MediaLibraryFactory>((ref) {
  throw StateError('MediaLibraryFactory 尚未由应用组合层绑定');
});

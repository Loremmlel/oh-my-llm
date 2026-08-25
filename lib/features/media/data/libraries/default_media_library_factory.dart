import 'package:http/http.dart' as http;

import '../../application/models/media_library_source.dart';
import '../../application/ports/media_library.dart';
import '../../application/ports/media_library_factory.dart';
import 'local_media_library.dart';
import '../scanning/media_directory_scanner.dart';
import '../scanning/media_thumbnail_cache.dart';
import '../scanning/media_thumbnail_generator.dart';
import 'remote_media_library.dart';
import '../scanning/thumbnail_process_runner.dart';

/// 缩略图缓存工厂：按需构建一次缓存实例（默认取应用 Support 目录）。
typedef MediaThumbnailCacheFactory = Future<MediaThumbnailCache> Function();

/// 按来源类型选择具体媒体库的默认工厂。
///
/// 本地 source 构造一套共享同一扫描器的 scanner/cache/generator；
/// 远程 source 直接构造 [RemoteMediaLibrary]。本地分支不检查
/// [Platform]，也不打开 peer client。
final class DefaultMediaLibraryFactory implements MediaLibraryFactory {
  DefaultMediaLibraryFactory({
    required this._peerHttpClient,
    MediaThumbnailCacheFactory? cacheFactory,
    this._processRunner = const DartThumbnailProcessRunner(),
  }) : _cacheFactory = cacheFactory ?? MediaThumbnailCache.defaultLocation;

  final http.Client _peerHttpClient;
  final MediaThumbnailCacheFactory _cacheFactory;
  final ThumbnailProcessRunner _processRunner;

  @override
  Future<MediaLibrary> open(MediaLibrarySource source) async {
    return switch (source) {
      LocalMediaLibrarySource(:final rootDirectory) => await _openLocal(
        rootDirectory,
      ),
      RemoteMediaLibrarySource(:final baseUri) => RemoteMediaLibrary(
        baseUri: baseUri,
        httpClient: _peerHttpClient,
      ),
    };
  }

  Future<LocalMediaLibrary> _openLocal(String rootDirectory) async {
    final scanner = MediaDirectoryScanner(rootDirectory);
    final cache = await _cacheFactory();
    return LocalMediaLibrary(
      scanner: scanner,
      cache: cache,
      generator: MediaThumbnailGenerator(
        scanner: scanner,
        processRunner: _processRunner,
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:oh_my_llm/features/media/application/models/media_library_source.dart';
import 'package:oh_my_llm/features/media/data/libraries/default_media_library_factory.dart';
import 'package:oh_my_llm/features/media/data/libraries/local_media_library.dart';
import 'package:oh_my_llm/features/media/data/scanning/media_thumbnail_cache.dart';
import 'package:oh_my_llm/features/media/data/libraries/remote_media_library.dart';
import 'package:oh_my_llm/features/media/data/scanning/thumbnail_process_runner.dart';

void main() {
  test(
    '本地 source 打开 LocalMediaLibrary，远程 source 打开 RemoteMediaLibrary',
    () async {
      final root = await Directory.systemTemp.createTemp('omll_factory_');
      addTearDown(() => root.delete(recursive: true));
      final cacheDir = Directory(
        '${root.path}${Platform.pathSeparator}.factory-cache',
      );

      final factory = DefaultMediaLibraryFactory(
        peerHttpClient: MockClient((_) async => http.Response('', 500)),
        cacheFactory: () async => MediaThumbnailCache.custom(cacheDir),
        processRunner: const DartThumbnailProcessRunner(),
      );

      expect(
        await factory.open(LocalMediaLibrarySource(root.path)),
        isA<LocalMediaLibrary>(),
      );
      expect(
        await factory.open(
          RemoteMediaLibrarySource(Uri.parse('http://192.168.1.5:8080')),
        ),
        isA<RemoteMediaLibrary>(),
      );
    },
  );

  test('打开本地 source 对 peer client 零调用', () async {
    // 只要本地路径误用 peer client，回调即抛错让测试立即失败——
    // 比计数断言更响亮地证明本地打开与列表都不走 HTTP。
    var requestCount = 0;
    final root = await Directory.systemTemp.createTemp('omll_factory_');
    addTearDown(() => root.delete(recursive: true));
    final cacheDir = Directory(
      '${root.path}${Platform.pathSeparator}.factory-cache',
    );

    final factory = DefaultMediaLibraryFactory(
      peerHttpClient: MockClient((_) async {
        requestCount++;
        throw StateError('local source used peer HTTP');
      }),
      cacheFactory: () async => MediaThumbnailCache.custom(cacheDir),
      processRunner: const DartThumbnailProcessRunner(),
    );

    final library = await factory.open(LocalMediaLibrarySource(root.path));
    // 本地库上的列表操作同样不得触达 peer client
    final items = await library.listDirectory('/');
    expect(items, isEmpty);
    expect(requestCount, 0);
  });
}

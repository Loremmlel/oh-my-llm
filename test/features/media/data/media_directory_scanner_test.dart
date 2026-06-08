import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/data/media_directory_scanner.dart';

void main() {
  group('MediaDirectoryScanner.resolvePath', () {
    late Directory tempRoot;
    late MediaDirectoryScanner scanner;
    late Directory subDir;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('media_scanner_test_');
      subDir = Directory('${tempRoot.path}${Platform.pathSeparator}subdir');
      subDir.createSync();
      File('${subDir.path}${Platform.pathSeparator}test.jpg').writeAsStringSync(
        'fake image content',
      );
    });

    tearDown(() {
      tempRoot.deleteSync(recursive: true);
    });

    MediaDirectoryScanner _createScanner() {
      return MediaDirectoryScanner(tempRoot.path);
    }

    test('正常路径解析返回绝对路径', () {
      scanner = _createScanner();
      final resolved = scanner.resolvePath('/');
      expect(resolved.toLowerCase(), tempRoot.absolute.path.toLowerCase());
    });

    test('子目录路径解析正确', () {
      scanner = _createScanner();
      final resolved = scanner.resolvePath('/subdir');
      expect(
        resolved.toLowerCase(),
        subDir.absolute.path.toLowerCase(),
      );
    });

    test('中文路径正常解析', () {
      final chineseDir = Directory(
        '${tempRoot.path}${Platform.pathSeparator}妹妹',
      );
      chineseDir.createSync();
      File('${chineseDir.path}${Platform.pathSeparator}照片.jpg')
          .writeAsStringSync('photo');

      scanner = _createScanner();
      final resolved = scanner.resolvePath('/妹妹');
      expect(
        resolved.toLowerCase(),
        chineseDir.absolute.path.toLowerCase(),
      );
    });

    group('路径穿越检测', () {
      setUp(() {
        scanner = _createScanner();
      });

      test('../ 穿越被拒绝', () {
        expect(
          () => scanner.resolvePath('/../etc'),
          throwsA(isA<PathTraversalException>()),
        );
      });

      test('多层 ../ 穿越被拒绝', () {
        expect(
          () => scanner.resolvePath('/subdir/../../../'),
          throwsA(isA<PathTraversalException>()),
        );
      });

      test('以 / 开头但含 .. 被拒绝', () {
        expect(
          () => scanner.resolvePath('/../..'),
          throwsA(isA<PathTraversalException>()),
        );
      });
    });

    test('不检查路径存在性（调用方自行判断）', () {
      scanner = _createScanner();
      // 不存在的路径不会抛异常（仅有路径穿越才抛）
      final resolved = scanner.resolvePath('/不存在的路径');
      expect(resolved, isNotEmpty);
      // 但文件/目录确实不存在
      expect(File(resolved).existsSync(), isFalse);
    });
  });

  group('MediaDirectoryScanner.scan', () {
    late Directory tempRoot;
    late MediaDirectoryScanner scanner;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('media_scan_test_');
      scanner = MediaDirectoryScanner(tempRoot.path);

      // 创建测试目录结构
      Directory('${tempRoot.path}${Platform.pathSeparator}folderB').createSync();
      Directory('${tempRoot.path}${Platform.pathSeparator}folderA').createSync();
      File('${tempRoot.path}${Platform.pathSeparator}bbb.mp4').writeAsStringSync(
        'video',
      );
      File('${tempRoot.path}${Platform.pathSeparator}aaa.mp4').writeAsStringSync(
        'video',
      );
    });

    tearDown(() {
      tempRoot.deleteSync(recursive: true);
    });

    test('排序：文件夹在前，文件在后，同类型按名称升序', () async {
      final items = await scanner.scan('/');

      expect(items.length, 4);
      // 前两个是文件夹（字母序）
      expect(items[0].name, 'folderA');
      expect(items[0].isDirectory, isTrue);
      expect(items[1].name, 'folderB');
      expect(items[1].isDirectory, isTrue);
      // 后两个是文件（字母序）
      expect(items[2].name, 'aaa.mp4');
      expect(items[2].isDirectory, isFalse);
      expect(items[3].name, 'bbb.mp4');
      expect(items[3].isDirectory, isFalse);
    });

    test('扫描不存在的目录抛出 FileSystemException', () async {
      expect(
        () => scanner.scan('/不存在的目录'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('FileItem 包含 lastModified/mimeType/thumbnailUrl', () async {
      final items = await scanner.scan('/');

      final videoItem = items.firstWhere((i) => i.name == 'bbb.mp4');
      expect(videoItem.lastModified, isNonZero);
      expect(videoItem.mimeType, 'video/mp4');
      expect(videoItem.thumbnailUrl, isNotNull);
      expect(videoItem.thumbnailUrl, contains('/api/media/thumbnail/'));

      // 文件夹不应有 mimeType 和 thumbnailUrl
      final folderItem = items.firstWhere((i) => i.isDirectory);
      expect(folderItem.mimeType, isNull);
      expect(folderItem.thumbnailUrl, isNull);
    });
  });

  group('MediaDirectoryScanner.scanRecursiveVideos', () {
    late Directory tempRoot;
    late MediaDirectoryScanner scanner;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('media_recursive_test_');
      scanner = MediaDirectoryScanner(tempRoot.path);

      // 嵌套目录结构：
      // root/
      //   video1.mp4
      //   sub/
      //     video2.mkv
      //     deep/
      //       video3.avi
      //   images/
      //     photo.jpg
      //   empty/
      Directory('${tempRoot.path}${Platform.pathSeparator}sub'
              '${Platform.pathSeparator}deep')
          .createSync(recursive: true);
      Directory('${tempRoot.path}${Platform.pathSeparator}images').createSync();
      Directory('${tempRoot.path}${Platform.pathSeparator}empty').createSync();

      File('${tempRoot.path}${Platform.pathSeparator}video1.mp4')
          .writeAsStringSync('video1');
      File('${tempRoot.path}${Platform.pathSeparator}sub'
              '${Platform.pathSeparator}video2.mkv')
          .writeAsStringSync('video2');
      File('${tempRoot.path}${Platform.pathSeparator}sub'
              '${Platform.pathSeparator}deep${Platform.pathSeparator}video3.avi')
          .writeAsStringSync('video3');
      File('${tempRoot.path}${Platform.pathSeparator}images'
              '${Platform.pathSeparator}photo.jpg')
          .writeAsStringSync('photo');
    });

    tearDown(() {
      tempRoot.deleteSync(recursive: true);
    });

    test('递归收集所有视频文件，按名称排序', () async {
      final videos = await scanner.scanRecursiveVideos('/');

      expect(videos.length, 3);
      expect(videos[0].name, 'video1.mp4');
      expect(videos[1].name, 'video2.mkv');
      expect(videos[2].name, 'video3.avi');
    });

    test('每个视频条目包含 name 和 relativePath', () async {
      final videos = await scanner.scanRecursiveVideos('/');

      final deepVideo = videos.firstWhere((v) => v.name == 'video3.avi');
      expect(
        deepVideo.relativePath.toLowerCase(),
        endsWith('/sub/deep/video3.avi'.toLowerCase()),
      );
    });

    test('空目录返回空列表', () async {
      final videos = await scanner.scanRecursiveVideos('/empty');
      expect(videos, isEmpty);
    });

    test('纯图片目录返回空列表', () async {
      final videos = await scanner.scanRecursiveVideos('/images');
      expect(videos, isEmpty);
    });

    test('隐藏文件被过滤', () async {
      File('${tempRoot.path}${Platform.pathSeparator}.hidden.mp4')
          .writeAsStringSync('hidden');
      final videos = await scanner.scanRecursiveVideos('/');
      expect(videos.any((v) => v.name == '.hidden.mp4'), isFalse);
    });

    test('不存在的目录抛出 FileSystemException', () async {
      expect(
        () => scanner.scanRecursiveVideos('/不存在的目录'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('路径穿越被拒绝', () async {
      expect(
        () => scanner.scanRecursiveVideos('/../etc'),
        throwsA(isA<PathTraversalException>()),
      );
    });

    test('VideoItem toJson/fromJson 往返一致', () {
      const item = VideoItem(name: 'test.mp4', relativePath: '/sub/test.mp4');
      expect(VideoItem.fromJson(item.toJson()), equals(item));
    });
  });
}

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
      File(
        '${subDir.path}${Platform.pathSeparator}test.jpg',
      ).writeAsStringSync('fake image content');
    });

    tearDown(() {
      tempRoot.deleteSync(recursive: true);
    });

    MediaDirectoryScanner createScanner() {
      return MediaDirectoryScanner(tempRoot.path);
    }

    test('正常/子目录/中文路径解析为绝对路径', () {
      final chineseDir = Directory(
        '${tempRoot.path}${Platform.pathSeparator}妹妹',
      );
      chineseDir.createSync();
      File(
        '${chineseDir.path}${Platform.pathSeparator}照片.jpg',
      ).writeAsStringSync('photo');

      // 用 resolveSymbolicLinksSync 归一化真实路径：本机 %TEMP% 可能是 8.3 短名
      // (如 hinana~1)，而 resolvePath 内部走 resolveSymbolicLinksSync 返回长名，
      // 直接比 absolute.path 会在短名/长名不一致时误判（Win11 默认禁用 8.3 短名生成）。
      final cases = [
        (
          name: '根路径',
          input: '/',
          expected: tempRoot.resolveSymbolicLinksSync(),
        ),
        (
          name: '子目录',
          input: '/subdir',
          expected: subDir.resolveSymbolicLinksSync(),
        ),
        (
          name: '中文路径',
          input: '/妹妹',
          expected: chineseDir.resolveSymbolicLinksSync(),
        ),
      ];

      scanner = createScanner();
      for (final (:name, :input, :expected) in cases) {
        final resolved = scanner.resolvePath(input);
        expect(
          resolved.toLowerCase(),
          expected.toLowerCase(),
          reason: 'case: $name',
        );
      }
    });

    test('路径穿越被拒绝', () {
      scanner = createScanner();
      for (final path in ['/../etc', '/subdir/../../../', '/../..']) {
        expect(
          () => scanner.resolvePath(path),
          throwsA(isA<PathTraversalException>()),
          reason: 'path: $path',
        );
      }
    });

    test('不检查路径存在性（调用方自行判断）', () {
      scanner = createScanner();
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
      Directory(
        '${tempRoot.path}${Platform.pathSeparator}folderB',
      ).createSync();
      Directory(
        '${tempRoot.path}${Platform.pathSeparator}folderA',
      ).createSync();
      File(
        '${tempRoot.path}${Platform.pathSeparator}bbb.mp4',
      ).writeAsStringSync('video');
      File(
        '${tempRoot.path}${Platform.pathSeparator}aaa.mp4',
      ).writeAsStringSync('video');
    });

    tearDown(() {
      tempRoot.deleteSync(recursive: true);
    });

    test('排序：文件夹在前文件在后，FileItem 元数据完整', () async {
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

      // 文件条目带 lastModified/mimeType + 传输无关 hasThumbnail；
      // 缩略图端点由 DTO 序列化时推导，扫描器不拼接
      final videoItem = items.firstWhere((i) => i.name == 'bbb.mp4');
      expect(videoItem.lastModified, isNonZero);
      expect(videoItem.mimeType, 'video/mp4');
      expect(videoItem.hasThumbnail, isTrue);
      // 文件夹不应有 mimeType，也没有缩略图信号
      final folderItem = items.firstWhere((i) => i.isDirectory);
      expect(folderItem.mimeType, isNull);
      expect(folderItem.hasThumbnail, isFalse);
    });

    test('扫描不存在的目录抛出 FileSystemException', () async {
      expect(
        () => scanner.scan('/不存在的目录'),
        throwsA(isA<FileSystemException>()),
      );
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
      Directory(
        '${tempRoot.path}${Platform.pathSeparator}sub'
        '${Platform.pathSeparator}deep',
      ).createSync(recursive: true);
      Directory('${tempRoot.path}${Platform.pathSeparator}images').createSync();
      Directory('${tempRoot.path}${Platform.pathSeparator}empty').createSync();

      File(
        '${tempRoot.path}${Platform.pathSeparator}video1.mp4',
      ).writeAsStringSync('video1');
      File(
        '${tempRoot.path}${Platform.pathSeparator}sub'
        '${Platform.pathSeparator}video2.mkv',
      ).writeAsStringSync('video2');
      File(
        '${tempRoot.path}${Platform.pathSeparator}sub'
        '${Platform.pathSeparator}deep${Platform.pathSeparator}video3.avi',
      ).writeAsStringSync('video3');
      File(
        '${tempRoot.path}${Platform.pathSeparator}images'
        '${Platform.pathSeparator}photo.jpg',
      ).writeAsStringSync('photo');
    });

    tearDown(() {
      tempRoot.deleteSync(recursive: true);
    });

    test('递归收集视频：名称、相对路径与排序', () async {
      final videos = await scanner.scanRecursiveVideos('/');

      expect(videos.length, 3);
      expect(videos[0].name, 'video1.mp4');
      expect(videos[1].name, 'video2.mkv');
      expect(videos[2].name, 'video3.avi');

      final deepVideo = videos.firstWhere((v) => v.name == 'video3.avi');
      expect(
        deepVideo.relativePath.toLowerCase(),
        endsWith('/sub/deep/video3.avi'.toLowerCase()),
      );
    });

    test('空目录与纯图片目录返回空列表', () async {
      for (final (:name, :input) in [
        (name: '空目录', input: '/empty'),
        (name: '纯图片目录', input: '/images'),
      ]) {
        expect(
          await scanner.scanRecursiveVideos(input),
          isEmpty,
          reason: 'case: $name',
        );
      }
    });

    test('隐藏文件被过滤', () async {
      File(
        '${tempRoot.path}${Platform.pathSeparator}.hidden.mp4',
      ).writeAsStringSync('hidden');
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
  });
}

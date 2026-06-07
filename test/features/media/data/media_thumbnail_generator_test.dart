import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:oh_my_llm/features/media/data/media_directory_scanner.dart';
import 'package:oh_my_llm/features/media/data/media_thumbnail_generator.dart';

/// 使用 image 包生成有效图片字节数组。
List<int> _generateImageBytes(String ext) {
  final image = img.Image(width: 2, height: 2);
  image.setPixelRgba(0, 0, 255, 0, 0, 255);
  image.setPixelRgba(1, 0, 0, 255, 0, 255);
  image.setPixelRgba(0, 1, 0, 0, 255, 255);
  image.setPixelRgba(1, 1, 255, 255, 0, 255);

  switch (ext.toLowerCase()) {
    case 'png':
      return img.encodePng(image);
    case 'jpg':
    case 'jpeg':
      return img.encodeJpg(image, quality: 90);
    case 'gif':
      return img.encodeGif(image);
    default:
      throw ArgumentError('Unknown extension: $ext');
  }
}
// Note: WebP encoding not supported by image 4.8.0, but the decoder works fine.
// The generator correctly handles WebP input files at runtime.

void main() {
  group('MediaThumbnailGenerator', () {
    late Directory tempDir;
    late MediaDirectoryScanner scanner;
    late MediaThumbnailGenerator generator;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('thumbnail_gen_test_');
      scanner = MediaDirectoryScanner(tempDir.path);
      generator = MediaThumbnailGenerator(scanner: scanner);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    group('图片缩略图', () {
      for (final ext in ['png', 'jpg', 'gif']) {
        test('$ext 格式生成缩略图成功', () async {
          final imgFile = File('${tempDir.path}/test.$ext');
          await imgFile.writeAsBytes(_generateImageBytes(ext));

          final result = await generator.generate('/test.$ext');
          expect(result, isNotEmpty);
          // JPEG 以 0xFF 0xD8 开头
          expect(result[0], 0xFF);
          expect(result[1], 0xD8);
        });
      }

      test('损坏的图片文件抛出异常', () async {
        final imgFile = File('${tempDir.path}/bad.png');
        // 足够长的随机数据，确保任何图片解码器都无法识别
        final badData = List<int>.generate(256, (i) => i % 256);
        await imgFile.writeAsBytes(badData);

        expect(
          () => generator.generate('/bad.png'),
          throwsA(isA<Exception>()),
        );
      });

      test('不支持的文件类型抛出异常', () async {
        final txtFile = File('${tempDir.path}/test.txt');
        await txtFile.writeAsString('not an image');
        expect(
          () => generator.generate('/test.txt'),
          throwsA(isA<ThumbnailException>()),
        );
      });

      test('不存在的文件抛出 FileSystemException', () async {
        expect(
          () => generator.generate('/nonexistent.jpg'),
          throwsA(isA<FileSystemException>()),
        );
      });
    });

    group('视频缩略图', () {
      test('假视频文件或缺少 ffmpeg 时抛出异常', () async {
        final videoFile = File('${tempDir.path}/test.mp4');
        await videoFile.writeAsString('fake video content');

        try {
          await generator.generate('/test.mp4');
          fail('Expected an exception');
        } on ThumbnailException {
          // 预期：ffmpeg 未安装或无法解析假文件
        } on ProcessException {
          // ffmpeg 未安装时 Process.run 直接抛 ProcessException
        }
      });
    });
  });
}

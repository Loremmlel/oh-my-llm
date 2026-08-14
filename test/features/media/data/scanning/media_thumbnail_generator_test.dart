import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:oh_my_llm/features/media/data/scanning/media_directory_scanner.dart';
import 'package:oh_my_llm/features/media/data/scanning/media_thumbnail_generator.dart';
import 'package:oh_my_llm/features/media/data/scanning/thumbnail_process_runner.dart';

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
// 注：image 4.8.0 不支持 WebP 编码，但解码器可用；生成器在运行时能正确处理 WebP 输入。

/// 一次脚本化进程调用的记录（可执行文件、参数与 stdout 编码约定）。
final class _ProcessCall {
  const _ProcessCall(this.executable, this.arguments, this.stdoutEncoding);
  final String executable;
  final List<String> arguments;
  final Encoding? stdoutEncoding;
}

/// 按脚本顺序响应进程调用的假运行器，视频测试不依赖主机 ffmpeg 安装状态。
final class _ScriptedProcessRunner implements ThumbnailProcessRunner {
  final calls = <_ProcessCall>[];
  final responses = <Future<ThumbnailProcessResult> Function()>[];

  void enqueue(ThumbnailProcessResult result) {
    responses.add(() async => result);
  }

  void enqueueError(Object error) {
    responses.add(() => Future<ThumbnailProcessResult>.error(error));
  }

  @override
  Future<ThumbnailProcessResult> run(
    String executable,
    List<String> arguments, {
    Encoding? stdoutEncoding,
  }) {
    calls.add(_ProcessCall(executable, List.of(arguments), stdoutEncoding));
    return responses.removeAt(0)();
  }
}

void main() {
  group('MediaThumbnailGenerator', () {
    late Directory tempDir;
    late MediaDirectoryScanner scanner;
    late _ScriptedProcessRunner runner;
    late MediaThumbnailGenerator generator;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('thumbnail_gen_test_');
      scanner = MediaDirectoryScanner(tempDir.path);
      // 视频测试必须注入脚本化运行器，禁止依赖主机 ffmpeg 安装状态。
      runner = _ScriptedProcessRunner();
      generator = MediaThumbnailGenerator(
        scanner: scanner,
        processRunner: runner,
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    group('图片缩略图', () {
      test('png/jpg/gif 格式生成缩略图成功（统一输出 JPEG）', () async {
        for (final ext in ['png', 'jpg', 'gif']) {
          final imgFile = File('${tempDir.path}/test.$ext');
          await imgFile.writeAsBytes(_generateImageBytes(ext));

          final result = await generator.generate('/test.$ext');
          expect(result, isNotEmpty, reason: 'ext: $ext');
          // JPEG 以 0xFF 0xD8 开头
          expect(result[0], 0xFF, reason: 'ext: $ext');
          expect(result[1], 0xD8, reason: 'ext: $ext');
        }
      });

      test('损坏的图片文件抛出异常', () async {
        final imgFile = File('${tempDir.path}/bad.png');
        // 足够长的随机数据，确保任何图片解码器都无法识别
        final badData = List<int>.generate(256, (i) => i % 256);
        await imgFile.writeAsBytes(badData);

        expect(() => generator.generate('/bad.png'), throwsA(isA<Exception>()));
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
      // 版本检测成功：exitCode 0 即视为可用
      const versionOk = ThumbnailProcessResult(
        exitCode: 0,
        stdout: '',
        stderr: '',
      );

      /// 创建仅需存在于磁盘的假视频文件（进程调用已脚本化，文件内容无关）。
      Future<void> createVideoFile() async {
        await File(
          '${tempDir.path}/test.mp4',
        ).writeAsString('fake video content');
      }

      /// 时长探测成功结果（stdout 为时长文本）。
      ThumbnailProcessResult durationResult(String seconds) =>
          ThumbnailProcessResult(exitCode: 0, stdout: seconds, stderr: '');

      /// 提取成功结果，stdout 原样返回图片字节。
      ThumbnailProcessResult extractionResult(List<int> bytes) =>
          ThumbnailProcessResult(exitCode: 0, stdout: bytes, stderr: '');

      test('短视频成功：版本检测后取中间帧，提取调用带 -ss 且 stdout 为原始字节', () async {
        await createVideoFile();
        final jpeg = _generateImageBytes('jpg');

        runner.enqueue(versionOk); // ffmpeg -version
        runner.enqueue(versionOk); // ffprobe -version
        runner.enqueue(durationResult('8.0'));
        runner.enqueue(extractionResult(jpeg));

        final result = await generator.generate('/test.mp4');

        expect(result, jpeg);
        final extraction = runner.calls.last;
        expect(extraction.executable, 'ffmpeg');
        expect(extraction.arguments, contains('-ss'));
        expect(extraction.arguments, contains('4.0'));
        expect(extraction.stdoutEncoding, isNull);
      });

      test('ffprobe 返回字节型 stdout 时仍能解析时长（真实 Process.run 默认返回字节）', () async {
        await createVideoFile();
        final jpeg = _generateImageBytes('jpg');
        runner.enqueue(versionOk);
        runner.enqueue(versionOk);
        // 字节型 duration stdout：DartThumbnailProcessRunner.run 的 stdoutEncoding 参数
        // 默认 null，真实 Process.run(..., stdoutEncoding: null) 返回 List<int> 而非 String。
        runner.enqueue(
          ThumbnailProcessResult(
            exitCode: 0,
            stdout: utf8.encode('8.0'),
            stderr: '',
          ),
        );
        runner.enqueue(extractionResult(jpeg));

        final result = await generator.generate('/test.mp4');

        expect(result, jpeg);
      });

      test('同一生成器两次生成：版本检测仅一次，长视频取第 5 秒帧', () async {
        await createVideoFile();
        final jpeg = _generateImageBytes('jpg');

        // 第一次生成：可用性检测 + 短视频中间帧
        runner.enqueue(versionOk);
        runner.enqueue(versionOk);
        runner.enqueue(durationResult('8.0'));
        runner.enqueue(extractionResult(jpeg));
        await generator.generate('/test.mp4');

        // 第二次生成：仅时长探测 + 提取，成功缓存使版本检测不再执行
        runner.enqueue(durationResult('20.0'));
        runner.enqueue(extractionResult(jpeg));
        final second = await generator.generate('/test.mp4');

        expect(second, jpeg);
        // 第二次提取调用取第 5 秒帧
        final secondExtraction = runner.calls.last;
        expect(secondExtraction.arguments, contains('-ss'));
        expect(secondExtraction.arguments, contains('5.0'));
        // 两次生成共 6 次调用：版本检测（ffmpeg/ffprobe 各一次）未重复
        expect(runner.calls.length, 6);
        final versionCalls = runner.calls.where(
          (c) => c.arguments.contains('-version'),
        );
        expect(
          versionCalls.where((c) => c.executable == 'ffmpeg'),
          hasLength(1),
        );
        expect(
          versionCalls.where((c) => c.executable == 'ffprobe'),
          hasLength(1),
        );
      });

      test('ffmpeg/ffprobe 版本命令返回非零退出码时抛出未安装异常', () async {
        await createVideoFile();
        const failed = ThumbnailProcessResult(
          exitCode: 1,
          stdout: '',
          stderr: '',
        );
        for (final failing in ['ffmpeg', 'ffprobe']) {
          if (failing == 'ffmpeg') {
            runner.enqueue(failed);
            runner.enqueue(versionOk);
          } else {
            runner.enqueue(versionOk);
            runner.enqueue(failed);
          }
          await expectLater(
            generator.generate('/test.mp4'),
            throwsA(
              isA<ThumbnailException>().having(
                (e) => e.message,
                'message',
                contains('ffmpeg 未安装，无法生成视频缩略图'),
              ),
            ),
          );
        }
      });

      test('ffmpeg/ffprobe 版本命令抛出 ProcessException 时提示无法启动', () async {
        await createVideoFile();
        for (final failing in ['ffmpeg', 'ffprobe']) {
          if (failing == 'ffmpeg') {
            runner.enqueueError(
              ProcessException('ffmpeg', ['-version'], '模拟启动失败'),
            );
          } else {
            runner.enqueue(versionOk);
            runner.enqueueError(
              ProcessException('ffprobe', ['-version'], '模拟启动失败'),
            );
          }
          await expectLater(
            generator.generate('/test.mp4'),
            throwsA(
              isA<ThumbnailException>().having(
                (e) => e.message,
                'message',
                contains('ffmpeg 未安装或无法启动'),
              ),
            ),
          );
        }
      });

      test('ffmpeg 版本命令抛出其他异常时提示检测失败', () async {
        await createVideoFile();
        runner.enqueueError(Exception('模拟检测异常'));
        await expectLater(
          generator.generate('/test.mp4'),
          throwsA(
            isA<ThumbnailException>().having(
              (e) => e.message,
              'message',
              contains('ffmpeg 检测失败'),
            ),
          ),
        );
      });

      test('ffprobe 时长探测返回非零退出码时抛出无法获取时长异常', () async {
        await createVideoFile();
        runner.enqueue(versionOk);
        runner.enqueue(versionOk);
        runner.enqueue(
          const ThumbnailProcessResult(exitCode: 1, stdout: '', stderr: ''),
        );
        await expectLater(
          generator.generate('/test.mp4'),
          throwsA(
            isA<ThumbnailException>().having(
              (e) => e.message,
              'message',
              contains('无法获取视频时长'),
            ),
          ),
        );
      });

      const invalidDurations = <String, String>{
        'abc': 'abc',
        '0': '0',
        '-1': '-1',
      };
      for (final entry in invalidDurations.entries) {
        test('ffprobe 输出时长 ${entry.key} 时抛出无法解析时长异常', () async {
          await createVideoFile();
          runner.enqueue(versionOk);
          runner.enqueue(versionOk);
          runner.enqueue(
            ThumbnailProcessResult(
              exitCode: 0,
              stdout: entry.value,
              stderr: '',
            ),
          );
          await expectLater(
            generator.generate('/test.mp4'),
            throwsA(
              isA<ThumbnailException>().having(
                (e) => e.message,
                'message',
                contains('无法解析视频时长'),
              ),
            ),
          );
        });
      }

      test('ffmpeg 提取失败时异常包含退出码与 stderr 文本', () async {
        await createVideoFile();
        runner.enqueue(versionOk);
        runner.enqueue(versionOk);
        runner.enqueue(durationResult('8.0'));
        runner.enqueue(
          const ThumbnailProcessResult(
            exitCode: 1,
            stdout: <int>[],
            stderr: 'mock extraction error',
          ),
        );
        await expectLater(
          generator.generate('/test.mp4'),
          throwsA(
            isA<ThumbnailException>().having(
              (e) => e.message,
              'message',
              allOf(contains('exit=1'), contains('mock extraction error')),
            ),
          ),
        );
      });

      test('ffmpeg 提取失败时字节 stderr 解码后出现在异常中', () async {
        await createVideoFile();
        // 用 ASCII 文本：生产代码以 String.fromCharCodes 解码字节 stderr
        final stderrBytes = utf8.encode('mock stderr bytes');
        runner.enqueue(versionOk);
        runner.enqueue(versionOk);
        runner.enqueue(durationResult('8.0'));
        runner.enqueue(
          ThumbnailProcessResult(
            exitCode: 1,
            stdout: <int>[],
            stderr: stderrBytes,
          ),
        );
        await expectLater(
          generator.generate('/test.mp4'),
          throwsA(
            isA<ThumbnailException>().having(
              (e) => e.message,
              'message',
              contains('mock stderr bytes'),
            ),
          ),
        );
      });

      test('ffmpeg 提取返回空 stdout 时抛出未输出数据异常', () async {
        await createVideoFile();
        runner.enqueue(versionOk);
        runner.enqueue(versionOk);
        runner.enqueue(durationResult('8.0'));
        runner.enqueue(
          const ThumbnailProcessResult(
            exitCode: 0,
            stdout: <int>[],
            stderr: '',
          ),
        );
        await expectLater(
          generator.generate('/test.mp4'),
          throwsA(
            isA<ThumbnailException>().having(
              (e) => e.message,
              'message',
              contains('ffmpeg 未输出数据'),
            ),
          ),
        );
      });
    });
  });
}

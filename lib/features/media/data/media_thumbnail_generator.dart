import 'dart:io';

import 'package:image/image.dart' as img;

import 'media_directory_scanner.dart';
import 'media_mime_types.dart';

/// 缩略图生成器。
///
/// 图片: 使用 `package:image` 缩放至 256px（最长边），输出 JPEG。
/// 视频: 调用 ffmpeg 取帧（<10s 中间帧，≥10s 第 5 秒帧），输出 JPEG。
///
/// 首次视频请求时自动检测 ffmpeg/ffprobe 可用性并缓存结果。
/// 若 ffmpeg 未安装，所有视频缩略图请求将直接抛出 [ThumbnailException]。
class MediaThumbnailGenerator {
  final MediaDirectoryScanner _scanner;

  /// 缩略图最长边像素。
  static const int thumbnailMaxSize = 256;

  /// JPEG 质量 (0-100)。
  static const int jpegQuality = 80;

  /// ffmpeg/ffprobe 操作超时（秒）。
  static const int ffmpegTimeoutSeconds = 30;

  /// ffmpeg 可用性缓存：null = 未检测，true = 可用，false = 不可用。
  bool? _ffmpegAvailable;

  MediaThumbnailGenerator({required MediaDirectoryScanner scanner})
      : _scanner = scanner;

  /// 生成缩略图，返回 JPEG 字节数组。
  ///
  /// [relativePath] 是客户端请求的相对路径。
  /// 抛出 [FileSystemException] 若文件不存在。
  /// 抛出 [ThumbnailException] 若生成失败或 ffmpeg 未安装。
  Future<List<int>> generate(String relativePath) async {
    final resolvedPath = _scanner.resolvePath(relativePath);
    final file = File(resolvedPath);
    if (!file.existsSync()) {
      throw FileSystemException('文件不存在', resolvedPath);
    }

    final ext = extensionFromFileName(relativePath);
    if (isImageFile(relativePath)) {
      return _generateImageThumbnail(resolvedPath);
    } else if (isVideoFile(relativePath)) {
      return _generateVideoThumbnail(resolvedPath);
    } else {
      throw ThumbnailException('不支持的文件类型: $ext');
    }
  }

  /// 图片缩略图：读取 → 解码 → 缩放 → 编码 JPEG。
  Future<List<int>> _generateImageThumbnail(String resolvedPath) async {
    final bytes = await File(resolvedPath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw ThumbnailException('无法解码图片: $resolvedPath');
    }

    // 缩放，保持宽高比，最长边 ≤ thumbnailMaxSize
    final resized = img.copyResize(
      decoded,
      width: thumbnailMaxSize,
      height: thumbnailMaxSize,
      maintainAspect: true,
    );

    return img.encodeJpg(resized, quality: jpegQuality);
  }

  /// 视频缩略图：调用 ffmpeg 取帧。
  ///
  /// 时长 < 10s → 取中间帧（duration / 2）
  /// 时长 ≥ 10s → 取第 5 秒帧
  Future<List<int>> _generateVideoThumbnail(String resolvedPath) async {
    // — 检查 ffmpeg 可用性（首次调用时检测并缓存） —
    await _ensureFfmpegAvailable();

    // 1. 获取视频时长（秒）
    final duration = await _getVideoDuration(resolvedPath);

    // 2. 计算取帧时间点
    final seekSeconds = duration < 10 ? duration / 2.0 : 5.0;

    // 3. 调用 ffmpeg 取帧，输出到 stdout
    final result = await Process.run(
      'ffmpeg',
      [
        '-ss', seekSeconds.toStringAsFixed(1),
        '-i', resolvedPath,
        '-vframes', '1',
        '-f', 'image2pipe',
        '-vcodec', 'mjpeg',
        '-q:v', '3',           // 质量等级 2-5，3 = 接近原图
        '-loglevel', 'error',   // 只输出错误
        '-y',                   // 覆盖输出
        '-',
      ],
      stdoutEncoding: null, // raw bytes
    ).timeout(
      const Duration(seconds: ffmpegTimeoutSeconds),
      onTimeout: () => throw ThumbnailException('ffmpeg 执行超时（${ffmpegTimeoutSeconds}s）'),
    );

    if (result.exitCode != 0) {
      final stderrMsg = result.stderr is String
          ? result.stderr as String
          : (result.stderr is List<int>
              ? String.fromCharCodes(result.stderr as List<int>)
              : '');
      throw ThumbnailException('ffmpeg 失败 (exit=${result.exitCode}): $stderrMsg');
    }

    final stdoutBytes = result.stdout as List<int>;
    if (stdoutBytes.isEmpty) {
      throw ThumbnailException('ffmpeg 未输出数据');
    }

    return stdoutBytes;
  }

  /// 通过 ffprobe 获取视频时长（秒）。
  Future<double> _getVideoDuration(String filePath) async {
    final result = await Process.run(
      'ffprobe',
      [
        '-v', 'error',
        '-show_entries', 'format=duration',
        '-of', 'default=noprint_wrappers=1:nokey=1',
        filePath,
      ],
    ).timeout(
      const Duration(seconds: ffmpegTimeoutSeconds),
      onTimeout: () => throw ThumbnailException('ffprobe 执行超时'),
    );

    if (result.exitCode != 0) {
      throw ThumbnailException('无法获取视频时长');
    }

    final output = (result.stdout as String).trim();
    final duration = double.tryParse(output);
    if (duration == null || duration <= 0) {
      throw ThumbnailException('无法解析视频时长: $output');
    }

    return duration;
  }

  /// 检测 ffmpeg 和 ffprobe 是否在 PATH 中可用。
  ///
  /// 成功结果缓存到 [_ffmpegAvailable]，后续调用直接返回。
  /// 失败结果不缓存——下次调用会重新检测，允许运行时安装 ffmpeg 后自动恢复。
  Future<void> _ensureFfmpegAvailable() async {
    if (_ffmpegAvailable == true) return;

    try {
      final ffmpegResult = await Process.run('ffmpeg', ['-version'])
          .timeout(const Duration(seconds: 5));
      final ffprobeResult = await Process.run('ffprobe', ['-version'])
          .timeout(const Duration(seconds: 5));
      _ffmpegAvailable = ffmpegResult.exitCode == 0 && ffprobeResult.exitCode == 0;
    } on ProcessException catch (e) {
      // 仅缓存成功结果，失败时保留原始错误信息供诊断
      throw ThumbnailException('ffmpeg 未安装或无法启动: ${e.message}');
    } on Exception catch (e) {
      throw ThumbnailException('ffmpeg 检测失败: $e');
    }

    if (!_ffmpegAvailable!) {
      throw ThumbnailException('ffmpeg 未安装，无法生成视频缩略图');
    }
  }

}

/// 缩略图生成异常。
class ThumbnailException implements Exception {
  final String message;
  const ThumbnailException(this.message);

  @override
  String toString() => 'ThumbnailException: $message';
}

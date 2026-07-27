import 'dart:convert';
import 'dart:io';

/// 可替换的外部进程调用结果，便于缩略图逻辑在不启动 ffmpeg 的情况下测试。
final class ThumbnailProcessResult {
  const ThumbnailProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final Object stdout;
  final Object stderr;
}

/// 缩略图生成需要的外部进程调用边界。
abstract interface class ThumbnailProcessRunner {
  Future<ThumbnailProcessResult> run(
    String executable,
    List<String> arguments, {
    Encoding? stdoutEncoding,
  });
}

/// 默认 Dart 进程实现；媒体 feature 中唯一调用 [Process.run] 的位置。
final class DartThumbnailProcessRunner implements ThumbnailProcessRunner {
  const DartThumbnailProcessRunner();

  @override
  Future<ThumbnailProcessResult> run(
    String executable,
    List<String> arguments, {
    Encoding? stdoutEncoding,
  }) async {
    final result = await Process.run(
      executable,
      arguments,
      stdoutEncoding: stdoutEncoding,
    );
    return ThumbnailProcessResult(
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
    );
  }
}

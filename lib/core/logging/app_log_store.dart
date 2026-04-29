import 'dart:io';

/// 文件日志存储：负责创建、追加写入、按阈值清空。
final class AppLogStore {
  AppLogStore._({required File file, required this.maxBytes}) : _file = file;

  static const defaultLogFileName = 'network.log';
  static const defaultMaxBytes = 1024 * 1024;

  final File _file;
  final int maxBytes;
  Future<void> _operation = Future<void>.value();

  static Future<AppLogStore> open({
    required String directoryPath,
    String fileName = defaultLogFileName,
    int maxBytes = defaultMaxBytes,
  }) async {
    final directory = Directory(directoryPath);
    await directory.create(recursive: true);
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return AppLogStore._(file: file, maxBytes: maxBytes);
  }

  Future<void> appendLine(String line) {
    _operation = _operation.then((_) async {
      await _ensureExists();
      await _rotateIfExceeded();
      await _file.writeAsString('$line\n', mode: FileMode.append, flush: true);
      await _rotateIfExceeded();
    });
    return _operation;
  }

  Future<void> clear({String? reason}) {
    _operation = _operation.then((_) async {
      await _ensureExists();
      await _file.writeAsString('', flush: true);
      if (reason != null && reason.isNotEmpty) {
        final now = DateTime.now().toIso8601String();
        await _file.writeAsString(
          '[$now] [log-cleared] $reason\n',
          mode: FileMode.append,
          flush: true,
        );
      }
    });
    return _operation;
  }

  Future<void> _ensureExists() async {
    if (await _file.exists()) {
      return;
    }
    await _file.create(recursive: true);
  }

  Future<void> _rotateIfExceeded() async {
    final length = await _file.length();
    if (length <= maxBytes) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    await _file.writeAsString(
      '[$now] [log-rotated] exceeded $maxBytes bytes, log reset.\n',
      flush: true,
    );
  }
}

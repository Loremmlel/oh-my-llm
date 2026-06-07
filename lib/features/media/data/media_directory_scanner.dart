import 'dart:io';

import '../domain/models/file_item.dart';

/// 路径穿越异常。
class PathTraversalException implements Exception {
  final String path;
  const PathTraversalException(this.path);

  @override
  String toString() => '路径穿越被拒绝: $path';
}

/// 服务端目录扫描器。
///
/// 负责扫描本地文件系统并返回 [FileItem] 列表，
/// 包含路径穿越防护和排序逻辑。
///
/// 构造时不执行 I/O——根目录的符号链接解析延迟到首次 [scan] 调用，
/// 避免无效根目录阻止服务端启动。
class MediaDirectoryScanner {
  /// 用户配置的原始根目录路径。
  final String _rawRoot;

  /// 懒加载的规范化根目录绝对路径。
  String? _resolvedRoot;

  MediaDirectoryScanner(String rootDirectory) : _rawRoot = rootDirectory;

  /// 返回已规范化的根目录绝对路径（首次访问时解析）。
  String get resolvedRoot {
    _resolvedRoot ??= Directory(_rawRoot).absolute.resolveSymbolicLinksSync();
    return _resolvedRoot!;
  }

  /// 验证相对路径并在根目录内解析为绝对路径。
  ///
  /// 执行以下安全检查：
  /// 1. 规范化 relativePath（确保以 `/` 开头）
  /// 2. 检查 raw 路径中是否含 `..`（最可靠的穿越检测，不依赖文件系统 API）
  /// 3. 与 [resolvedRoot] 拼接
  /// 4. 解析所有符号链接
  /// 5. 检查解析后路径是否在根目录内（符号链接穿越防护）
  ///
  /// 返回解析后的绝对路径字符串。
  /// 抛出 [PathTraversalException] 若检测到路径穿越。
  ///
  /// **注意**：不检查目标是否存在——调用方需自行判断。
  String resolvePath(String relativePath) {
    final normalizedPath = _normalizePath(relativePath);

    // 穿越检测：仅拒绝路径段恰好为 ".." 的（避免误杀含 .. 的合法文件名）
    // request.uri.path 已由 Dart 自动 URL-decode，%2e 等编码已还原
    if (normalizedPath.split('/').any((s) => s == '..')) {
      throw PathTraversalException(normalizedPath);
    }

    final joined = _joinPath(resolvedRoot, normalizedPath);

    // 尝试解析符号链接
    String resolved;
    try {
      resolved = File(joined).resolveSymbolicLinksSync();
    } on FileSystemException catch (e) {
      // 仅路径不存在（ENOENT）时回退到拼接结果
      // 权限拒绝等错误应向上传播，不能静默回退（回退路径可能绕过符号链接检测）
      if (e.osError?.errorCode == 2) {
        resolved = joined;
      } else {
        rethrow;
      }
    }

    // 符号链接解析后的二次检查（防止符号链接指向根目录外）
    if (!_isPathUnderRoot(resolved)) {
      throw PathTraversalException(normalizedPath);
    }
    return resolved;
  }

  /// 扫描指定目录，返回 [FileItem] 列表。
  ///
  /// [relativePath] 是客户端请求的相对路径，如 `"/"` 或 `"/sister/video"`。
  ///
  /// 抛出 [PathTraversalException] 当路径穿越被检测到。
  /// 抛出 [FileSystemException] 当目录不存在或无法访问。
  Future<List<FileItem>> scan(String relativePath) async {
    final resolvedPath = resolvePath(relativePath);

    final dir = Directory(resolvedPath);
    if (!dir.existsSync()) {
      throw FileSystemException('目录不存在', resolvedPath);
    }

    // 使用异步 list() 避免阻塞事件循环
    final entities = await dir.list().toList();

    final items = <FileItem>[];
    for (final entity in entities) {
      // 获取文件名
      final name = _fileName(entity.path);
      // 跳过 Unix 风格隐藏文件
      if (name.startsWith('.')) continue;

      // 跳过 Windows 隐藏文件（如 desktop.ini、Thumbs.db）
      if (_isWindowsHidden(entity)) continue;

      final isDir = entity is Directory;
      final stat = entity.statSync();

      // 计算相对路径：去除根目录前缀
      final relToRoot = entity.absolute.path.substring(resolvedRoot.length);
      // Windows 反斜杠统一为正斜杠
      final relativePath = '/${relToRoot.replaceAll('\\', '/')}'
          .replaceAll(RegExp(r'/+'), '/');

      items.add(FileItem(
        name: name,
        isDirectory: isDir,
        sizeBytes: isDir ? 0 : stat.size,
        relativePath: relativePath,
      ));
    }

    // 排序：文件夹在前，文件在后；同类型按名称升序（忽略大小写）
    items.sort((a, b) {
      final dirCmp =
          (b.isDirectory ? 1 : 0).compareTo(a.isDirectory ? 1 : 0);
      if (dirCmp != 0) return dirCmp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return items;
  }

  /// 检查是否是 Windows 隐藏文件（FILE_ATTRIBUTE_HIDDEN）。
  ///
  /// 仅当运行在 Windows 上时检查；其他平台始终返回 false。
  bool _isWindowsHidden(FileSystemEntity entity) {
    if (!Platform.isWindows) return false;
    // 在 Windows 上，隐藏属性映射到 mode 的 owner-read 位为 0
    // 但实际上 Dart 的 FileStat 在 Windows 上不直接暴露 FILE_ATTRIBUTE_HIDDEN
    // 作为可靠替代，过滤 Windows 已知的隐藏系统文件名
    const knownHidden = {'desktop.ini', 'Thumbs.db', 'thumbs.db'};
    return knownHidden.contains(_fileName(entity.path).toLowerCase());
  }

  /// 拼接服务端路径，处理 Windows 路径分隔符差异。
  String _joinPath(String base, String relative) {
    // 移除 base 末尾的 / 和 \
    final cleanBase = base.replaceAll(RegExp(r'[/\\]+$'), '');
    // 移除 relative 开头的 /
    final cleanRel = relative.replaceAll(RegExp(r'^[/\\]+'), '');
    return '$cleanBase${Platform.pathSeparator}$cleanRel';
  }

  /// 规范化客户端提供的相对路径，确保以 `/` 开头。
  String _normalizePath(String relativePath) {
    if (relativePath.isEmpty || relativePath == '/') return '/';
    return relativePath.startsWith('/') ? relativePath : '/$relativePath';
  }

  /// 检查 resolvedPath 是否在根目录内（Windows 忽略大小写）。
  bool _isPathUnderRoot(String resolvedPath) {
    // 规范化后的根目录可能不含尾部 /，追加分隔符防止 /root-other 前缀绕过
    final rootWithSep = resolvedRoot.endsWith(Platform.pathSeparator)
        ? resolvedRoot
        : '$resolvedRoot${Platform.pathSeparator}';
    return resolvedPath.toLowerCase().startsWith(rootWithSep.toLowerCase()) ||
        resolvedPath.toLowerCase() == resolvedRoot.toLowerCase();
  }

  /// 从路径中提取文件名。
  String _fileName(String path) {
    // 同时处理 / 和 \ 两种分隔符
    final lastSep = _lastIndexOfAny(path, ['/', '\\']);
    return lastSep >= 0 ? path.substring(lastSep + 1) : path;
  }

  int _lastIndexOfAny(String s, List<String> chars) {
    var idx = -1;
    for (final c in chars) {
      final i = s.lastIndexOf(c);
      if (i > idx) idx = i;
    }
    return idx;
  }
}

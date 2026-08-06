import 'dart:io';

import 'architecture/import_boundary_checker.dart';

/// 依赖边界 CLI：从仓库根运行 `dart run tool/check_import_boundaries.dart`。
///
/// 退出码：0 = 零违规；1 = 存在违规或 stale allowance；2 = 运行目录错误。
Future<void> main() async {
  final libDirectory = Directory('lib');
  if (!libDirectory.existsSync()) {
    stderr.writeln('错误：找不到 lib/ 目录，请在仓库根目录运行本工具。');
    exitCode = 2;
    return;
  }
  final checker = ImportBoundaryChecker(policy: architecturePolicy);
  final violations = checker.checkDirectory(
    libDirectory,
    verifyAllowlistUsage: true,
  );
  for (final violation in violations) {
    final location = violation.line > 0
        ? '${violation.sourcePath}:${violation.line}'
        : violation.sourcePath;
    stdout.writeln('$location [${violation.ruleId}] ${violation.message}');
  }
  stdout.writeln('检查 ${checker.fileCount} 个文件，${violations.length} 条违规');
  if (violations.isNotEmpty) {
    exitCode = 1;
  }
}

import 'dart:io';

/// 一条解析后的 import/export 依赖边（source 与 target 均为仓库相对路径）。
class ImportEdge {
  const ImportEdge({required this.sourcePath, required this.targetPath});

  final String sourcePath;
  final String targetPath;

  @override
  bool operator ==(Object other) =>
      other is ImportEdge &&
      other.sourcePath == sourcePath &&
      other.targetPath == targetPath;

  @override
  int get hashCode => Object.hash(sourcePath, targetPath);

  @override
  String toString() => '$sourcePath -> $targetPath';
}

/// 架构策略：只承载存量债务的精确例外。
class ArchitecturePolicy {
  const ArchitecturePolicy({this.legacyApplicationDataEdges = const {}});

  /// application → data 的精确放行边（key 是完整规范化路径对，value 是保留原因）。
  final Map<ImportEdge, String> legacyApplicationDataEdges;
}

/// 一条架构违规。
class ArchitectureViolation {
  const ArchitectureViolation({
    required this.ruleId,
    required this.sourcePath,
    required this.line,
    required this.importUri,
    required this.resolvedTarget,
    required this.message,
  });

  final String ruleId;
  final String sourcePath;

  /// 1-based 行号；stale allowance 条目为 0。
  final int line;
  final String importUri;
  final String? resolvedTarget;
  final String message;
}

/// 生产架构策略：Settings 的 7 条存量 application→data 旧边。
///
/// 新增例外必须同步修改本策略、补 reason、补测试并经过 review；
/// 不允许从配置文件读取任意通配符。
/// 不能是 const：`ImportEdge` 重写了 `==`，Dart 常量求值器要求 const map 的
/// key 具备 primitive equality，自定义 == 的类做 const key 是编译错误；
/// 运行时按值匹配不受影响。
final architecturePolicy = ArchitecturePolicy(
  legacyApplicationDataEdges: {
    ImportEdge(
      sourcePath: 'lib/features/settings/application/preferences/chat_defaults_controller.dart',
      targetPath: 'lib/features/settings/data/chat_defaults_repository.dart',
    ): '现有 concrete SharedPreferences repository；不属于已迁移的 port 闭环。',
    ImportEdge(
      sourcePath: 'lib/features/settings/application/prompts/fixed_prompt_sequences_controller.dart',
      targetPath: 'lib/features/settings/data/prompts/fixed_prompt_sequence_repository.dart',
    ): '现有 concrete/top-level SQLite repository；保持既有行为。',
    ImportEdge(
      sourcePath: 'lib/features/settings/application/providers/llm_model_configs_controller.dart',
      targetPath: 'lib/features/settings/data/providers/llm_model_config_repository.dart',
    ): '现有 concrete repository；Settings 全组不在本次迁移范围。',
    ImportEdge(
      sourcePath: 'lib/features/settings/application/prompts/memory_prompts_controller.dart',
      targetPath: 'lib/features/settings/data/prompts/sqlite_memory_prompt_repository.dart',
    ): '现有 SQLite repository object；metadata/persistence ownership 另行处理。',
    ImportEdge(
      sourcePath: 'lib/features/settings/application/providers/model_catalog_workflow.dart',
      targetPath: 'lib/features/settings/data/providers/model_list_client.dart',
    ): '现有 concrete HTTP client；没有 application-owned port。',
    ImportEdge(
      sourcePath: 'lib/features/settings/application/prompts/preset_prompts_controller.dart',
      targetPath:
          'lib/features/settings/data/prompts/preset_prompt_repository.dart',
    ): '现有 concrete/top-level SQLite repository。',
    ImportEdge(
      sourcePath: 'lib/features/settings/application/prompts/template_prompts_controller.dart',
      targetPath:
          'lib/features/settings/data/prompts/template_prompt_repository.dart',
    ): '现有 concrete/top-level SQLite repository。',
  },
);

/// 扫描 lib/**/*.dart 的 import/export 依赖方向，判定分层违规。
class ImportBoundaryChecker {
  ImportBoundaryChecker({required this.policy});

  final ArchitecturePolicy policy;

  /// 最近一次扫描的文件数。
  int fileCount = 0;

  static const _frameworkPackages = {
    'flutter',
    'flutter_riverpod',
    'riverpod',
    'riverpod_annotation',
    'sqlite3',
  };

  // 不要求首行就带分号：conditional import 常把 `if (...)` 续行放到下一行，
  // 分号在最后一行的末尾，单行正则会漏掉整个语句（见下方扫描循环的续行合并）。
  static final _directivePattern = RegExp(r'^(import|export)\s+(.+)$');
  // 不用 raw string：raw 字符串里 `\"` 是字面反斜杠+引号，双引号会提前终止字符串；
  // 普通字符串中 `\"` 才是转义引号，正则值即为 `'([^']+)'|"([^"]+)"`。
  static final _uriPattern = RegExp("'([^']+)'|\"([^\"]+)\"");

  /// 用内存 source map 检查（fixture 测试用）。key 是 `lib/...` 仓库相对路径。
  List<ArchitectureViolation> checkSources(
    Map<String, String> sources, {
    bool verifyAllowlistUsage = false,
  }) {
    fileCount = sources.length;
    final violations = <ArchitectureViolation>[];
    final consumedAllowances = <ImportEdge>{};

    final sortedPaths = sources.keys.toList()..sort();
    for (final sourcePath in sortedPaths) {
      // Windows 仓库可能以 CRLF 检出：`\r` 会卡住 `$` 锚点导致整行 directive
      // 失配（Dart RegExp 的 `$` 不认行尾 `\r`），先剥掉再逐行扫描。
      final lines = sources[sourcePath]!
          .split('\n')
          .map((l) => l.replaceAll('\r', ''))
          .toList();
      var inBlockComment = false;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (inBlockComment) {
          if (line.contains('*/')) inBlockComment = false;
          continue;
        }
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//')) continue;
        if (trimmed.contains('/*')) {
          // import/export 行不会同时携带块注释，含块注释的行保守跳过。
          if (!line.contains('*/')) inBlockComment = true;
          continue;
        }
        final directive = _directivePattern.firstMatch(trimmed);
        if (directive == null) continue;
        var body = directive.group(2)!;
        // 语句未到分号就吞并后续行（conditional import 的 `if (...)` 续行），
        // 保证每个分支的 URI literal 都被 `_uriPattern` 检查到。
        var j = i;
        while (!body.contains(';') && j + 1 < lines.length) {
          j++;
          body += '\n${lines[j].trimLeft()}';
        }
        // show/hide 子句不携带引号字符串，不会产生伪 URI。
        for (final uriMatch in _uriPattern.allMatches(body)) {
          final uri = uriMatch.group(1) ?? uriMatch.group(2)!;
          final resolved = _resolveImport(sourcePath, uri);
          final violation = _checkEdge(
            sourcePath: sourcePath,
            line: i + 1,
            importUri: uri,
            resolvedTarget: resolved,
            consumedAllowances: consumedAllowances,
          );
          if (violation != null) violations.add(violation);
        }
      }
    }

    if (verifyAllowlistUsage) {
      for (final edge in policy.legacyApplicationDataEdges.keys) {
        if (!consumedAllowances.contains(edge)) {
          violations.add(
            ArchitectureViolation(
              ruleId: 'STALE_ALLOWANCE',
              sourcePath: edge.sourcePath,
              line: 0,
              importUri: edge.targetPath,
              resolvedTarget: edge.targetPath,
              message: 'allowlist 例外已不再被消费，请删除对应条目',
            ),
          );
        }
      }
    }

    violations.sort(_compareViolations);
    return violations;
  }

  /// 扫描真实 lib 目录（conformance 测试与 CLI 用）。
  List<ArchitectureViolation> checkDirectory(
    Directory libDirectory, {
    bool verifyAllowlistUsage = false,
  }) {
    final sources = <String, String>{};
    final libRoot = libDirectory.absolute.path;
    for (final entity in libDirectory.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final relative = entity.absolute.path
            .substring(libRoot.length + 1)
            .replaceAll(Platform.pathSeparator, '/');
        sources['lib/$relative'] = entity.readAsStringSync();
      }
    }
    return checkSources(sources, verifyAllowlistUsage: verifyAllowlistUsage);
  }

  ArchitectureViolation? _checkEdge({
    required String sourcePath,
    required int line,
    required String importUri,
    required String? resolvedTarget,
    required Set<ImportEdge> consumedAllowances,
  }) {
    final sourceLayer = _featureLayer(sourcePath);
    final targetLayer = resolvedTarget == null
        ? null
        : _featureLayer(resolvedTarget);

    if (sourceLayer == 'presentation' && targetLayer == 'data') {
      return _violation(
        'PRESENTATION_TO_DATA',
        sourcePath,
        line,
        importUri,
        resolvedTarget,
        'presentation 不得导入 data',
      );
    }
    if (sourceLayer == 'presentation' &&
        resolvedTarget != null &&
        resolvedTarget.startsWith('lib/core/persistence/')) {
      return _violation(
        'PRESENTATION_TO_CORE_PERSISTENCE',
        sourcePath,
        line,
        importUri,
        resolvedTarget,
        'presentation 不得导入 core/persistence',
      );
    }
    if (sourcePath.startsWith('lib/core/') &&
        resolvedTarget != null &&
        resolvedTarget.startsWith('lib/features/')) {
      return _violation(
        'CORE_TO_FEATURE',
        sourcePath,
        line,
        importUri,
        resolvedTarget,
        'core 不得导入 feature',
      );
    }
    if (sourcePath.contains('/domain/')) {
      final pkg = _packageName(importUri);
      if (pkg != null && _frameworkPackages.contains(pkg)) {
        return _violation(
          'DOMAIN_FRAMEWORK_DEPENDENCY',
          sourcePath,
          line,
          importUri,
          resolvedTarget,
          'domain 不得依赖框架包 package:$pkg',
        );
      }
    }
    if (sourceLayer == 'application' && targetLayer == 'data') {
      final edge = ImportEdge(
        sourcePath: sourcePath,
        targetPath: resolvedTarget!,
      );
      if (policy.legacyApplicationDataEdges.containsKey(edge)) {
        consumedAllowances.add(edge);
      } else {
        return _violation(
          'APPLICATION_TO_DATA',
          sourcePath,
          line,
          importUri,
          resolvedTarget,
          'application 不得导入 data（存量例外见 architecturePolicy）',
        );
      }
    }
    return null;
  }

  /// 解析 import URI：本包 package → `lib/...`；外部 package/dart: 保留 null；
  /// 相对 URI 按 source 目录解析 `.`/`..`。
  String? _resolveImport(String sourcePath, String uri) {
    if (uri.startsWith('package:oh_my_llm/')) {
      return 'lib/${uri.substring('package:oh_my_llm/'.length)}';
    }
    if (uri.startsWith('package:') || uri.startsWith('dart:')) {
      return null;
    }
    final sourceDir = sourcePath.substring(0, sourcePath.lastIndexOf('/'));
    return _normalizePath('$sourceDir/$uri');
  }

  String _normalizePath(String path) {
    final out = <String>[];
    for (final part in path.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (out.isNotEmpty) out.removeLast();
        continue;
      }
      out.add(part);
    }
    return out.join('/');
  }

  /// 返回 `features/<feature>/<layer>` 中的 layer；非 feature 路径返回 null。
  String? _featureLayer(String path) {
    final segments = path.split('/');
    final featureIndex = segments.indexOf('features');
    if (featureIndex < 0 || featureIndex + 2 >= segments.length) return null;
    return segments[featureIndex + 2];
  }

  String? _packageName(String uri) {
    if (!uri.startsWith('package:')) return null;
    return uri.substring('package:'.length).split('/').first;
  }

  ArchitectureViolation _violation(
    String ruleId,
    String sourcePath,
    int line,
    String importUri,
    String? resolvedTarget,
    String message,
  ) => ArchitectureViolation(
    ruleId: ruleId,
    sourcePath: sourcePath,
    line: line,
    importUri: importUri,
    resolvedTarget: resolvedTarget,
    message: message,
  );

  /// 结果按 sourcePath → line → ruleId → resolvedTarget 排序，
  /// 保证 Windows/Linux 输出一致。
  int _compareViolations(ArchitectureViolation a, ArchitectureViolation b) {
    final bySource = a.sourcePath.compareTo(b.sourcePath);
    if (bySource != 0) return bySource;
    if (a.line != b.line) return a.line - b.line;
    final byRule = a.ruleId.compareTo(b.ruleId);
    if (byRule != 0) return byRule;
    return (a.resolvedTarget ?? '').compareTo(b.resolvedTarget ?? '');
  }
}

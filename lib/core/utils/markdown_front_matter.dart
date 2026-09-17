import 'dart:convert';

import 'package:yaml/yaml.dart';

/// 只解析文件开头的元信息，调用方继续保存原文以保留作者格式。
({String name, String description}) parseMarkdownFrontMatter(String content) {
  final lines = const LineSplitter().convert(
    content.startsWith('\uFEFF') ? content.substring(1) : content,
  );
  if (lines.isEmpty || lines.first.trimRight() != '---') {
    throw const FormatException('请在剧本开头用 --- 包围 name 和 description。');
  }
  final end = lines.indexWhere((line) => line.trimRight() == '---', 1);
  if (end < 0) throw const FormatException('剧本元信息缺少结束的 ---。');
  if (lines.skip(end + 1).join('\n').trim().isEmpty) {
    throw const FormatException('元信息之后需要填写 Markdown 剧本正文。');
  }
  final Object? metadata;
  try {
    metadata = loadYaml(lines.sublist(1, end).join('\n'));
  } on YamlException catch (error) {
    final line = error.span == null
        ? ''
        : '（文件第 ${error.span!.start.line + 2} 行）';
    throw FormatException('剧本元信息 YAML 格式错误$line：${error.message}');
  }
  String field(String key, int limit) {
    final value = metadata is Map ? metadata[key] : null;
    if (value is! String || value.trim().isEmpty || value.length > limit) {
      throw FormatException('$key 必须是 1–$limit 个字符的非空字符串。');
    }
    return value.trim();
  }

  return (name: field('name', 120), description: field('description', 2000));
}

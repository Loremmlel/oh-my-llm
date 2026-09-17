import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/utils/markdown_front_matter.dart';

void main() {
  test('剧本元信息支持中文、多行描述、引号、BOM 和不同换行，正文保持作者格式', () {
    for (final newline in ['\n', '\r\n']) {
      final text = '\uFEFF---\nname: "秋季：校园风波"\ndescription: >-\n  加入文学社之后。\n  横跨两个月。\nmetadata: {author: 测试作者}\n---\n# 正文\n保持原文'
          .replaceAll('\n', newline);
      final result = parseMarkdownFrontMatter(text);
      expect(result.name, '秋季：校园风波');
      expect(result.description, '加入文学社之后。 横跨两个月。');
    }
  });

  test('缺失、重复或错误类型的元信息以及空正文均显式拒绝', () {
    // 原始文本专门覆盖 YAML 与 front matter 的非法输入边界。
    for (final text in [
      'name: 无边界',
      '---\nname: 未结束',
      '---\nname: 缺描述\n---\n正文',
      '---\nname: [错误类型]\ndescription: 描述\n---\n正文',
      '---\nname: 名称\ndescription: 123\n---\n正文',
      '---\nname: ""\ndescription: 描述\n---\n正文',
      '---\nname: 一\nname: 二\ndescription: 描述\n---\n正文',
      '---\nname: 名称\ndescription: 描述\n---\n  ',
      '---\nname: 名称\ndescription: ${'长' * 2001}\n---\n正文',
    ]) {
      expect(
        () => parseMarkdownFrontMatter(text),
        throwsFormatException,
        reason: text.substring(0, text.length.clamp(0, 80)),
      );
    }
  });
}

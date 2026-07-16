import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/chat/application/output_regex_processor.dart';
import 'package:oh_my_llm/features/settings/domain/models/output_processing_settings.dart';

void main() {
  group('applyOutputRegexRules', () {
    test('空内容或空规则原样返回', () {
      expect(applyOutputRegexRules('', const []), '');
      expect(applyOutputRegexRules('hello', const []), 'hello');
    });

    test('替换字为空时删除匹配内容', () {
      const rules = [OutputRegexRule(id: 'r', pattern: '极其', order: 0)];
      expect(applyOutputRegexRules('这个极其重要', rules), '这个重要');
    });

    test('替换字非空时替换匹配内容', () {
      const rules = [
        OutputRegexRule(id: 'r', pattern: '极其', replacement: '非常', order: 0),
      ];
      expect(applyOutputRegexRules('极其极其好', rules), '非常非常好');
    });

    test('多条规则按 order 升序链式应用', () {
      const rules = [
        OutputRegexRule(id: 'r2', pattern: 'b', replacement: 'c', order: 1),
        OutputRegexRule(id: 'r1', pattern: 'a', replacement: 'b', order: 0),
      ];
      // 先 a→b（aa→bb），再 b→c（bb→cc）
      expect(applyOutputRegexRules('aa', rules), 'cc');
    });

    test('禁用规则被跳过', () {
      const rules = [
        OutputRegexRule(id: 'r', pattern: '极其', order: 0, enabled: false),
      ];
      expect(applyOutputRegexRules('极其好', rules), '极其好');
    });

    test('空表达式规则被跳过', () {
      const rules = [OutputRegexRule(id: 'r', pattern: '', order: 0)];
      expect(applyOutputRegexRules('极其好', rules), '极其好');
    });

    test('无效正则表达式被静默跳过，不影响其它规则', () {
      const rules = [
        OutputRegexRule(id: 'bad', pattern: '(', order: 0),
        OutputRegexRule(id: 'ok', pattern: '好', replacement: '棒', order: 1),
      ];
      expect(applyOutputRegexRules('好', rules), '棒');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/output_processing_settings.dart';

void main() {
  group('OutputRegexRule', () {
    test('toJson → fromJson round-trip 保留全部字段', () {
      const rule = OutputRegexRule(
        id: 'rule-1',
        title: '过滤极其',
        pattern: '极其',
        replacement: '非常',
        order: 3,
        enabled: false,
      );
      final restored = OutputRegexRule.fromJson(rule.toJson());
      expect(restored, rule);
    });

    test('fromJson 缺失字段回退到默认值', () {
      final rule = OutputRegexRule.fromJson({'id': 'only-id'});
      expect(rule.id, 'only-id');
      expect(rule.title, '');
      expect(rule.pattern, '');
      expect(rule.replacement, '');
      expect(rule.order, 0);
      expect(rule.enabled, isTrue);
    });

    test('copyWith 覆盖指定字段', () {
      const rule = OutputRegexRule(id: 'r', pattern: 'a', enabled: true);
      final next = rule.copyWith(pattern: 'b', enabled: false);
      expect(next.id, 'r');
      expect(next.pattern, 'b');
      expect(next.enabled, isFalse);
    });
  });

  group('OutputProcessingSettings', () {
    test('toJson → fromJson round-trip 保留规则列表', () {
      const settings = OutputProcessingSettings(
        rules: [
          OutputRegexRule(id: 'r1', pattern: 'a', order: 0),
          OutputRegexRule(id: 'r2', pattern: 'b', order: 1),
        ],
      );
      final restored = OutputProcessingSettings.fromJson(settings.toJson());
      expect(restored, settings);
    });

    test('fromJson 对非列表 rules 返回空设置', () {
      final settings = OutputProcessingSettings.fromJson({'rules': 'oops'});
      expect(settings.rules, isEmpty);
    });
  });
}

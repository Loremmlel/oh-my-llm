import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/font_size_settings.dart';

void main() {
  group('FontSizeSettings', () {
    test('默认 bodyFontSize 为 14', () {
      const settings = FontSizeSettings();
      expect(settings.bodyFontSize, 14);
    });

    test('fromJson 正常解析', () {
      final settings = FontSizeSettings.fromJson({'bodyFontSize': 18});
      expect(settings.bodyFontSize, 18);
    });

    test('fromJson 缺失字段默认为 14', () {
      final settings = FontSizeSettings.fromJson({});
      expect(settings.bodyFontSize, 14);
    });

    test('fromJson 非 num 值抛出类型错误', () {
      expect(
        () => FontSizeSettings.fromJson({'bodyFontSize': 'invalid'}),
        throwsA(isA<TypeError>()),
      );
    });

    test('toJson → fromJson round-trip', () {
      const settings = FontSizeSettings(bodyFontSize: 20);
      final restored = FontSizeSettings.fromJson(settings.toJson());
      expect(restored, settings);
    });

    test('copyWith 部分覆盖', () {
      const settings = FontSizeSettings(bodyFontSize: 16);
      final updated = settings.copyWith(bodyFontSize: 22);
      expect(updated.bodyFontSize, 22);
    });
  });
}

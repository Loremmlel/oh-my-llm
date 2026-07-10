import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/custom_headers_config.dart';

void main() {
  group('CustomHeadersConfig', () {
    test('toHeaderMap 空列表返回空 map', () {
      const config = CustomHeadersConfig();
      expect(config.toHeaderMap(), isEmpty);
    });

    test('toHeaderMap 正常转换', () {
      const config = CustomHeadersConfig(headers: [
        CustomHeaderEntry(key: 'X-Custom', value: 'foo'),
        CustomHeaderEntry(key: 'Authorization', value: 'Bearer token'),
      ]);
      final map = config.toHeaderMap();
      expect(map['X-Custom'], 'foo');
      expect(map['Authorization'], 'Bearer token');
    });

    test('toHeaderMap 同 key 后者覆盖前者', () {
      const config = CustomHeadersConfig(headers: [
        CustomHeaderEntry(key: 'X-Custom', value: 'first'),
        CustomHeaderEntry(key: 'X-Custom', value: 'second'),
      ]);
      expect(config.toHeaderMap()['X-Custom'], 'second');
    });

    test('toHeaderMap 跳过空 key', () {
      const config = CustomHeadersConfig(headers: [
        CustomHeaderEntry(key: '', value: 'ignored'),
        CustomHeaderEntry(key: 'X-Valid', value: 'valid'),
      ]);
      final map = config.toHeaderMap();
      expect(map, isNot(contains('')));
      expect(map['X-Valid'], 'valid');
    });

    test('toHeaderMap 跳过仅空白字符的 key', () {
      const config = CustomHeadersConfig(headers: [
        CustomHeaderEntry(key: '  ', value: 'ignored'),
      ]);
      expect(config.toHeaderMap(), isEmpty);
    });

    test('fromJson null headers 返回空列表', () {
      final config = CustomHeadersConfig.fromJson({});
      expect(config.headers, isEmpty);
    });

    test('toJson → fromJson round-trip', () {
      const config = CustomHeadersConfig(headers: [
        CustomHeaderEntry(key: 'X-A', value: '1'),
      ]);
      final restored = CustomHeadersConfig.fromJson(config.toJson());
      expect(restored, config);
    });
  });

  group('CustomHeaderEntry', () {
    test('fromJson 缺失字段默认为空字符串', () {
      final entry = CustomHeaderEntry.fromJson({});
      expect(entry.key, '');
      expect(entry.value, '');
    });
  });
}

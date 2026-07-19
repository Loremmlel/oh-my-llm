import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/settings/application/custom_headers_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/custom_headers_config.dart';

void main() {
  group('CustomHeadersController', () {
    late SharedPreferences sp;
    late ProviderContainer container;
    late CustomHeadersController controller;

    Future<void> boot(Map<String, Object> initial) async {
      SharedPreferences.setMockInitialValues(initial);
      sp = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(container.dispose);
      controller = container.read(customHeadersProvider.notifier);
    }

    CustomHeadersConfig readState() => container.read(customHeadersProvider);

    test('无持久化数据时返回空配置', () async {
      await boot({});
      expect(readState().headers, isEmpty);
    });

    test('从持久化恢复已有配置', () async {
      await boot({});
      await controller.addHeader('X-A', '1');
      await controller.addHeader('X-B', '2');

      final revived = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(revived.dispose);

      final restored = revived.read(customHeadersProvider);
      expect(restored.headers.length, 2);
      expect(restored.headers[0].key, 'X-A');
      expect(restored.headers[1].key, 'X-B');
    });

    test('持久化数据损坏时降级为空配置', () async {
      await boot({customHeadersStorageKey: 'not-json'});
      expect(readState().headers, isEmpty);
    });

    test('addHeader 添加一条', () async {
      await boot({});
      await controller.addHeader('X-New', 'val');

      expect(readState().headers.length, 1);
      expect(readState().headers.first.key, 'X-New');
      expect(readState().headers.first.value, 'val');
      expect(sp.getString(customHeadersStorageKey), isNotNull);
    });

    test('addHeader 多次追加', () async {
      await boot({});
      await controller.addHeader('X-A', '1');
      await controller.addHeader('X-B', '2');

      expect(readState().headers.length, 2);
      expect(readState().headers[0].key, 'X-A');
      expect(readState().headers[1].key, 'X-B');
    });

    test('removeHeader 正常删除', () async {
      await boot({});
      await controller.addHeader('X-A', '1');
      await controller.addHeader('X-B', '2');

      await controller.removeHeader(0);

      expect(readState().headers.length, 1);
      expect(readState().headers.first.key, 'X-B');
    });

    test('removeHeader 越界 index 不报错', () async {
      await boot({});
      await controller.addHeader('X-A', '1');

      await controller.removeHeader(-1);
      expect(readState().headers.length, 1);

      await controller.removeHeader(99);
      expect(readState().headers.length, 1);
    });

    test('updateHeader 更新指定位置', () async {
      await boot({});
      await controller.addHeader('X-Old', 'old');

      await controller.updateHeader(0, 'X-New', 'new');

      expect(readState().headers[0].key, 'X-New');
      expect(readState().headers[0].value, 'new');
      expect(sp.getString(customHeadersStorageKey), isNotNull);
    });

    test('updateHeader 越界 index 不报错', () async {
      await boot({});
      await controller.addHeader('X-A', '1');

      await controller.updateHeader(-1, 'k', 'v');
      expect(readState().headers[0].key, 'X-A');

      await controller.updateHeader(99, 'k', 'v');
      expect(readState().headers[0].key, 'X-A');
    });

    test('save 后重建容器能恢复完整配置', () async {
      await boot({});
      await controller.addHeader('X-A', '1');
      await controller.addHeader('X-B', '2');

      final revived = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(revived.dispose);

      final restored = revived.read(customHeadersProvider);
      expect(restored.headers.length, 2);
      expect(restored.toHeaderMap(), {'X-A': '1', 'X-B': '2'});
    });
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/history/history_browse_preferences_controller.dart';

void main() {
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  ProviderContainer createContainer({HistoryPageSizeWriter? writer}) {
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        if (writer != null)
          historyPageSizeWriterProvider.overrideWithValue(writer),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('HistoryBrowsePreferencesController', () {
    test('无持久化值时回退默认容量 20', () {
      final c = createContainer();

      expect(c.read(historyBrowsePreferencesProvider), 20);
    });

    test('恢复持久化的合法容量', () async {
      SharedPreferences.setMockInitialValues({
        'app.feature.history.page_size': 50,
      });
      preferences = await SharedPreferences.getInstance();
      final c = createContainer();

      expect(c.read(historyBrowsePreferencesProvider), 50);
    });

    test('持久化非法容量回退默认 20', () async {
      for (final raw in const [0, -5, 99]) {
        SharedPreferences.setMockInitialValues({
          'app.feature.history.page_size': raw,
        });
        preferences = await SharedPreferences.getInstance();
        final c = createContainer();

        expect(
          c.read(historyBrowsePreferencesProvider),
          20,
          reason: '$raw 应视为非法',
        );
      }
    });

    test('save 持久化所选容量并同步内存状态', () async {
      final c = createContainer();

      await c.read(historyBrowsePreferencesProvider.notifier).save(50);

      expect(c.read(historyBrowsePreferencesProvider), 50);
      expect(preferences.getInt('app.feature.history.page_size'), 50);
    });

    test('save 非法容量不生效', () async {
      final c = createContainer();

      await c.read(historyBrowsePreferencesProvider.notifier).save(999);

      expect(c.read(historyBrowsePreferencesProvider), 20);
      expect(preferences.containsKey('app.feature.history.page_size'), isFalse);
    });

    test('写入失败时保留内存选择且不向外抛出', () async {
      final c = createContainer(
        writer: (_) => Future<bool>.error(Exception('disk full')),
      );

      await c.read(historyBrowsePreferencesProvider.notifier).save(10);

      expect(c.read(historyBrowsePreferencesProvider), 10);
    });

    test('历史偏好使用独立存储键不与收藏共用', () {
      expect(historyPageSizeStorageKey, 'app.feature.history.page_size');
      expect(
        historyPageSizeStorageKey,
        isNot('app.feature.favorites.page_size'),
      );
    });
  });
}

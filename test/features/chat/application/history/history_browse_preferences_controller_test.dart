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
    test('save 持久化所选容量并同步内存状态', () async {
      final c = createContainer();

      await c.read(historyBrowsePreferencesProvider.notifier).save(50);

      expect(c.read(historyBrowsePreferencesProvider), 50);
      expect(preferences.getInt('app.feature.history.page_size'), 50);
      expect(createContainer().read(historyBrowsePreferencesProvider), 50);
    });

    test('写入失败时保留内存选择且不向外抛出', () async {
      final c = createContainer(
        writer: (_) => Future<bool>.error(Exception('disk full')),
      );

      await c.read(historyBrowsePreferencesProvider.notifier).save(10);

      expect(c.read(historyBrowsePreferencesProvider), 10);
    });
  });
}

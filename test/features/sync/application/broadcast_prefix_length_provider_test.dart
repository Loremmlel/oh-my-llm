import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/sync/application/broadcast_prefix_length_provider.dart';
import 'package:oh_my_llm/features/sync/domain/models/broadcast_prefix_length.dart';

void main() {
  group('selectedBroadcastPrefixLengthProvider', () {
    late SharedPreferences preferences;

    ProviderContainer buildContainer() {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('SharedPreferences 无存储时默认 /24', () async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      final container = buildContainer();

      expect(
        container.read(selectedBroadcastPrefixLengthProvider),
        BroadcastPrefixLength.p24,
      );
    });

    test('SharedPreferences 存储 16 时还原为 /16', () async {
      SharedPreferences.setMockInitialValues({
        'sync.broadcast_prefix_length': 16,
      });
      preferences = await SharedPreferences.getInstance();
      final container = buildContainer();

      expect(
        container.read(selectedBroadcastPrefixLengthProvider),
        BroadcastPrefixLength.p16,
      );
    });

    test('SharedPreferences 存储 8 时还原为 /8', () async {
      SharedPreferences.setMockInitialValues({
        'sync.broadcast_prefix_length': 8,
      });
      preferences = await SharedPreferences.getInstance();
      final container = buildContainer();

      expect(
        container.read(selectedBroadcastPrefixLengthProvider),
        BroadcastPrefixLength.p8,
      );
    });

    test('SharedPreferences 存储非法值（如 20）时回退到 /24', () async {
      SharedPreferences.setMockInitialValues({
        'sync.broadcast_prefix_length': 20,
      });
      preferences = await SharedPreferences.getInstance();
      final container = buildContainer();

      expect(
        container.read(selectedBroadcastPrefixLengthProvider),
        BroadcastPrefixLength.p24,
      );
    });

    test('select(p16) 后 state 变为 /16，且 SharedPreferences 写入 16', () async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      final container = buildContainer();

      container
          .read(selectedBroadcastPrefixLengthProvider.notifier)
          .select(BroadcastPrefixLength.p16);

      expect(
        container.read(selectedBroadcastPrefixLengthProvider),
        BroadcastPrefixLength.p16,
      );
      expect(preferences.getInt('sync.broadcast_prefix_length'), 16);
    });

    test('select 当前值时不重复写入 SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      final container = buildContainer();

      // 默认是 /24，再选一次 /24
      container
          .read(selectedBroadcastPrefixLengthProvider.notifier)
          .select(BroadcastPrefixLength.p24);

      // 无副作用：getInt 返回 null（从未写入过）
      expect(preferences.getInt('sync.broadcast_prefix_length'), isNull);
    });
  });
}

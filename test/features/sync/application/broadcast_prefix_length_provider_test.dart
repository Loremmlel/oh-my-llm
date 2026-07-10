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

    for (final (name, init, expected) in <(String, Map<String, Object>, BroadcastPrefixLength)>[
      ('无存储', <String, Object>{}, BroadcastPrefixLength.p24),
      ('非法值 20', {'sync.broadcast_prefix_length': 20}, BroadcastPrefixLength.p24),
    ]) {
      test('SharedPreferences $name 时为 $expected', () async {
        SharedPreferences.setMockInitialValues(init);
        preferences = await SharedPreferences.getInstance();
        final container = buildContainer();

        expect(
          container.read(selectedBroadcastPrefixLengthProvider),
          expected,
        );
      });
    }

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
  });
}

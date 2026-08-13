import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/composer/composer_collapsed_controller.dart';

void main() {
  group('ComposerCollapsedController', () {
    late SharedPreferences preferences;
    late ProviderContainer container;
    late ComposerCollapsedController controller;

    Future<void> boot(Map<String, Object> initial) async {
      SharedPreferences.setMockInitialValues(initial);
      preferences = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(container.dispose);
      controller = container.read(composerCollapsedProvider.notifier);
    }

    bool readState() => container.read(composerCollapsedProvider);

    test('从缺失、false、true 三种持久化状态恢复', () async {
      for (final entry in <MapEntry<Map<String, Object>, bool>>[
        const MapEntry({}, false),
        const MapEntry({'composer_isCollapsed': false}, false),
        const MapEntry({'composer_isCollapsed': true}, true),
      ]) {
        await boot(entry.key);
        expect(readState(), entry.value, reason: 'initial=${entry.key}');
      }
    });

    test('toggle 连续翻转两端状态并持久化最终值', () async {
      await boot({});

      controller.toggle();
      expect(readState(), isTrue);
      controller.toggle();
      expect(readState(), isFalse);
      controller.toggle();
      expect(readState(), isTrue);
      await Future.microtask(() {});

      expect(preferences.getBool('composer_isCollapsed'), isTrue);
    });

    test('setCollapsed 更新后可由新容器恢复', () async {
      await boot({});

      controller.setCollapsed(true);
      await Future.microtask(() {});

      final revived = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(revived.dispose);
      expect(revived.read(composerCollapsedProvider), isTrue);
    });
  });
}

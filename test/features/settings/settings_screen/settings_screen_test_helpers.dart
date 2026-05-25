import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/settings/presentation/settings_screen.dart';

import '../../../helpers/fixtures.dart';
import '../../../helpers/test_harness.dart';

const settingsLastTabIndexKey = 'settings.tab.last_index';

const tabLabels = ['服务商', '预设', '提示词', '其它'];

/// 切换到指定标签页。
Future<void> switchToTab(WidgetTester tester, int index) async {
  await tester.tap(find.text(tabLabels[index]));
  await tester.pumpAndSettle();
}

/// 挂载设置页并返回测试用数据库实例。
Future<AppDatabase> pumpSettingsScreen(
  WidgetTester tester, {
  required SharedPreferences preferences,
  Size size = const Size(1440, 1500),
  int initialTabIndex = 0,
}) async {
  await preferences.setInt(settingsLastTabIndexKey, initialTabIndex);

  // 设置空剪贴板，避免"新增"按钮的导入检测挂起平台通道
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': ''};
      }
      if (call.method == 'Clipboard.setData') {
        return null;
      }
      if (call.method == 'Clipboard.hasStrings') {
        return <String, dynamic>{'value': false};
      }
      return null;
    },
  );

  return pumpTestApp(
    tester,
    child: const SettingsScreen(),
    preferences: preferences,
    viewportSize: size,
  );
}

Future<SharedPreferences> createEmptyPreferences() async {
  return TestFixtures.seedPreferences();
}

/// 创建包含默认种子数据的 SharedPreferences 实例。
Future<SharedPreferences> createDefaultsSeededPreferences() async {
  return TestFixtures.seedPreferences(
    models: [
      TestFixtures.gpt41(),
      TestFixtures.claudeSonnet(),
    ],
    prompts: [
      TestFixtures.presetPrompt(id: 'prompt-1', name: '代码助手'),
    ],
  );
}

// ── Finder 工厂 ────────────────────────────────────────────

Finder providerNameField() =>
    find.byKey(const ValueKey('model-provider-name-field'));

Finder providerApiUrlField() =>
    find.byKey(const ValueKey('model-provider-api-url-field'));

Finder providerApiKeyField() =>
    find.byKey(const ValueKey('model-provider-api-key-field'));

Finder modelDisplayNameField() =>
    find.byKey(const ValueKey('model-config-display-name-field'));

Finder modelApiNameField() =>
    find.byKey(const ValueKey('model-config-api-name-field'));

Finder modelSupportsReasoningField() =>
    find.byKey(const ValueKey('model-config-supports-reasoning-field'));

Finder presetPromptNameField() =>
    find.byKey(const ValueKey('preset-prompt-name-field'));

Finder presetPromptTitleField() =>
    find.byKey(const ValueKey('preset-prompt-title-field'));

Finder presetPromptContentField() =>
    find.byKey(const ValueKey('preset-prompt-content-field'));

Finder fixedPromptSequenceNameField() =>
    find.byKey(const ValueKey('fixed-prompt-sequence-name-field'));

Finder fixedStepTitleField() =>
    find.byKey(const ValueKey('fixed-step-title-field'));

Finder fixedStepContentField() =>
    find.byKey(const ValueKey('fixed-step-content-field'));

Finder templatePromptTitleField() =>
    find.byKey(const ValueKey('template-prompt-title-field'));

Finder templatePromptContentField() =>
    find.byKey(const ValueKey('template-prompt-content-field'));

Finder templatePromptVariableField(String variableName) =>
    find.byKey(ValueKey('template-prompt-variable-field-$variableName'));

Finder memoryPromptNameField() =>
    find.byKey(const ValueKey('memory-prompt-name-field'));

Finder memoryPromptContentField() =>
    find.byKey(const ValueKey('memory-prompt-content-field'));

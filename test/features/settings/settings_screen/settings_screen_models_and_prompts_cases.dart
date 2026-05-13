import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/presentation/widgets/settings_card_grid.dart';
import 'package:oh_my_llm/features/settings/presentation/settings_screen.dart';

import 'settings_screen_test_helpers.dart';

void registerSettingsScreenModelsAndPromptsTests() {
  testWidgets(
    'settings screen supports provider and model CRUD flows',
    (tester) async {
      final preferences = await createEmptyPreferences();

      await pumpSettingsScreen(tester, preferences: preferences);

      expect(find.text('还没有服务商配置'), findsOneWidget);

      await tester.tap(find.text('新增服务商'));
      await tester.pumpAndSettle();

      await tester.enterText(providerNameField(), 'OpenAI 官方');
      await tester.enterText(
        providerApiUrlField(),
        'https://api.example.com/v1/chat/completions',
      );
      await tester.enterText(providerApiKeyField(), 'sk-test-12345678');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('OpenAI 官方'), findsWidgets);
      expect(find.text('当前服务商下还没有模型。'), findsOneWidget);

      await tester.tap(find.text('新增模型'));
      await tester.pumpAndSettle();

      await tester.enterText(modelDisplayNameField(), 'OpenAI 4.1');
      await tester.enterText(modelApiNameField(), 'gpt-4.1');
      await tester.tap(modelSupportsReasoningField());
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('OpenAI 4.1'), findsWidgets);
      expect(find.text('支持深度思考'), findsOneWidget);

      await tester.tap(find.text('编辑服务商'));
      await tester.pumpAndSettle();
      await tester.enterText(providerNameField(), 'OpenAI 官方 v2');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('OpenAI 官方 v2'), findsWidgets);

      await tester.tap(find.widgetWithText(OutlinedButton, '编辑').last);
      await tester.pumpAndSettle();
      await tester.enterText(modelDisplayNameField(), 'OpenAI 4.1 Turbo');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('OpenAI 4.1 Turbo'), findsWidgets);

      await tester.tap(find.widgetWithText(OutlinedButton, '删除').last);
      await tester.pumpAndSettle();

      expect(find.text('当前服务商下还没有模型。'), findsOneWidget);

      await tester.tap(find.text('删除服务商'));
      await tester.pumpAndSettle();

      expect(find.text('还没有服务商配置'), findsOneWidget);
    },
  );

  testWidgets(
    'settings screen keeps model list collapsed by default and expands on demand',
    (tester) async {
      final preferences = await createDefaultsSeededPreferences();

      await pumpSettingsScreen(
        tester,
        preferences: preferences,
        size: const Size(430, 932),
      );

      expect(find.text('API 模型名称：gpt-4.1'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('provider-models-toggle-provider-1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('API 模型名称：gpt-4.1'), findsOneWidget);
    },
  );

  testWidgets(
    'settings screen supports prompt template CRUD flows',
    (tester) async {
      final preferences = await createEmptyPreferences();

      await pumpSettingsScreen(tester, preferences: preferences);

      expect(find.text('还没有预设 Prompt'), findsOneWidget);

      await tester.tap(find.text('新增预设'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('preset-prompt-form-layout')),
        findsOneWidget,
      );
      await tester.enterText(presetPromptNameField(), '代码审阅');
      await tester.tap(find.text('新增条目'));
      await tester.pumpAndSettle();

      await tester.enterText(presetPromptTitleField(), '前置要求');
      await tester.enterText(
        presetPromptContentField(),
        '请检查这段代码的边界情况。',
      );
      await tester.tap(
        find.byKey(const ValueKey('preset-prompt-placement-field')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('后置').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('代码审阅'), findsWidgets);
      expect(find.textContaining('共 1 条消息'), findsOneWidget);

      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(presetPromptNameField()).controller?.text,
        '代码审阅',
      );
      expect(
        tester.widget<TextFormField>(presetPromptTitleField()).controller?.text,
        '前置要求',
      );
      expect(
        tester.widget<TextFormField>(presetPromptContentField()).controller?.text,
        '请检查这段代码的边界情况。',
      );
      await tester.enterText(presetPromptNameField(), '代码审阅 v2');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('代码审阅 v2'), findsWidgets);

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(find.text('还没有预设 Prompt'), findsOneWidget);
    },
  );

  testWidgets(
    'settings screen can duplicate prompt template with incremental suffix',
    (tester) async {
      final preferences = await createEmptyPreferences();
      await pumpSettingsScreen(tester, preferences: preferences);

      await tester.tap(find.text('新增预设'));
      await tester.pumpAndSettle();
      await tester.enterText(presetPromptNameField(), '代码审阅');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, '复制').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '复制').first);
      await tester.pumpAndSettle();

      expect(find.text('代码审阅（副本）'), findsWidgets);
      expect(find.text('代码审阅（副本 2）'), findsWidgets);
    },
  );

  testWidgets('prompt template dialog accepts multiple system messages', (
    tester,
  ) async {
    final preferences = await createEmptyPreferences();
    await pumpSettingsScreen(tester, preferences: preferences);

    await tester.tap(find.text('新增预设'));
    await tester.pumpAndSettle();
    await tester.enterText(presetPromptNameField(), '多 system 模板');

    Future<void> fillItem({
      required String title,
      required String content,
      required String roleLabel,
    }) async {
      await tester.tap(find.text('新增条目'));
      await tester.pumpAndSettle();
      await tester.enterText(presetPromptTitleField(), title);
      await tester.enterText(presetPromptContentField(), content);
      await tester.tap(find.byKey(const ValueKey('preset-prompt-role-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(roleLabel).last);
      await tester.pumpAndSettle();
    }

    await fillItem(title: '系统 1', content: '系统内容 1', roleLabel: 'System');
    await fillItem(title: '系统 2', content: '系统内容 2', roleLabel: 'System');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('多 system 模板'), findsWidgets);
    expect(find.textContaining('共 2 条消息'), findsOneWidget);
  });

  testWidgets(
    'prompt template dialog inserts a new item below selection and keeps groups ordered',
    (tester) async {
      final preferences = await createEmptyPreferences();

      await pumpSettingsScreen(
        tester,
        preferences: preferences,
        size: const Size(1440, 2200),
      );
      final masterPane = find.byKey(
        const ValueKey('preset-prompt-master-pane'),
      );
      final addItemButton = find
          .descendant(
            of: masterPane,
            matching: find.widgetWithText(OutlinedButton, '新增条目'),
          )
          .hitTestable();
      final presetList = find
          .descendant(of: masterPane, matching: find.byType(ListView))
          .hitTestable();

      Finder rawPresetTile(String title) {
        return find.descendant(of: masterPane, matching: find.text(title));
      }

      Finder presetTile(String title) {
        return rawPresetTile(title).hitTestable();
      }

      Future<void> ensurePresetTileVisible(String title) async {
        if (presetTile(title).evaluate().isNotEmpty) {
          return;
        }
        await tester.dragUntilVisible(
          rawPresetTile(title),
          presetList,
          const Offset(0, -240),
        );
        await tester.pumpAndSettle();
      }

      Future<String> selectedTitle() async {
        final titleField = tester.widget<TextFormField>(presetPromptTitleField());
        return titleField.controller?.text ?? '';
      }

      Future<void> fillSelectedItem(String title, String content) async {
        await tester.enterText(presetPromptTitleField(), title);
        await tester.enterText(presetPromptContentField(), content);
        await tester.pump();
      }

      await tester.tap(find.text('新增预设'));
      await tester.pumpAndSettle();
      await tester.enterText(presetPromptNameField(), '插入测试模板');

      await tester.tap(addItemButton);
      await tester.pumpAndSettle();
      expect(await selectedTitle(), startsWith('前置user'));
      await fillSelectedItem('前置1', '内容1');

      await tester.tap(addItemButton);
      await tester.pumpAndSettle();
      expect(await selectedTitle(), startsWith('前置user'));
      await fillSelectedItem('后置1', '内容2');

      await tester.tap(
        find.byKey(const ValueKey('preset-prompt-placement-field')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('后置').last);
      await tester.pumpAndSettle();

      await tester.tap(presetTile('前置1'));
      await tester.pumpAndSettle();
      await tester.tap(addItemButton);
      await tester.pumpAndSettle();
      expect(await selectedTitle(), startsWith('前置user'));
      await fillSelectedItem('前置1.5', '内容1.5');
      await ensurePresetTileVisible('后置1');

      expect(
        tester.getTopLeft(rawPresetTile('前置1')).dy,
        lessThan(tester.getTopLeft(rawPresetTile('前置1.5')).dy),
      );
      expect(
        tester.getTopLeft(rawPresetTile('前置1.5')).dy,
        lessThan(tester.getTopLeft(rawPresetTile('后置1')).dy),
      );

      await ensurePresetTileVisible('后置1');
      await tester.tap(presetTile('后置1'));
      await tester.pumpAndSettle();
      await tester.tap(addItemButton);
      await tester.pumpAndSettle();
      expect(await selectedTitle(), startsWith('后置user'));
      await fillSelectedItem('后置1.5', '内容1.5');
      await ensurePresetTileVisible('后置1.5');

      expect(
        tester.getTopLeft(rawPresetTile('后置1')).dy,
        lessThan(tester.getTopLeft(rawPresetTile('后置1.5')).dy),
      );

      final titleField = tester.widget<TextFormField>(presetPromptTitleField());
      final contentField = tester.widget<TextFormField>(
        presetPromptContentField(),
      );
      expect(titleField.controller?.text, '后置1.5');
      expect(contentField.controller?.text, '内容1.5');
    },
  );

  testWidgets(
    'prompt template dialog only keeps outer scroll on compact layout',
    (tester) async {
      final preferences = await createEmptyPreferences();

      await pumpSettingsScreen(
        tester,
        preferences: preferences,
        size: const Size(1440, 2200),
      );

      await tester.tap(find.text('新增预设'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-form-dialog-outer-scroll-view')),
        findsNothing,
      );

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      await pumpSettingsScreen(
        tester,
        preferences: preferences,
        size: const Size(430, 932),
      );

      final settingsList = find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(ListView),
      );
      final addPresetButton = find.widgetWithText(FilledButton, '新增预设');
      await tester.dragUntilVisible(
        addPresetButton,
        settingsList.first,
        const Offset(0, -300),
      );
      await tester.ensureVisible(addPresetButton);
      await tester.pumpAndSettle();
      await tester.tap(addPresetButton);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-form-dialog-outer-scroll-view')),
        findsOneWidget,
      );
    },
  );

  testWidgets('prompt template dialog keeps wide master header visible', (
    tester,
  ) async {
    final preferences = await createEmptyPreferences();

    await pumpSettingsScreen(
      tester,
      preferences: preferences,
      size: const Size(1440, 2200),
    );

    await tester.tap(find.text('新增预设'));
    await tester.pumpAndSettle();

    final masterPane = find.byKey(const ValueKey('preset-prompt-master-pane'));
    final addItemButton = find.descendant(
      of: masterPane,
      matching: find.widgetWithText(OutlinedButton, '新增条目'),
    );

    for (var index = 1; index <= 20; index++) {
      await tester.tap(addItemButton);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final header = find.descendant(
      of: masterPane,
      matching: find.text('预设 Prompt 条目'),
    );
    final presetList = find.descendant(
      of: masterPane,
      matching: find.byType(ListView),
    );
    final headerOffsetBefore = tester.getTopLeft(header);
    final titleField = tester.widget<TextFormField>(presetPromptTitleField());
    final latestAutoTitle = titleField.controller?.text ?? '';
    expect(latestAutoTitle, isNotEmpty);

    await tester.dragUntilVisible(
      find.text(latestAutoTitle),
      presetList,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text(latestAutoTitle), findsWidgets);
    expect(tester.getTopLeft(header).dy, headerOffsetBefore.dy);
    expect(addItemButton, findsOneWidget);
  });

  testWidgets('prompt template dialog locks wide detail pane scroll', (
    tester,
  ) async {
    final preferences = await createEmptyPreferences();

    await pumpSettingsScreen(
      tester,
      preferences: preferences,
      size: const Size(1440, 2200),
    );

    await tester.tap(find.text('新增预设'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '新增条目'));
    await tester.pumpAndSettle();

    final detailPane = find.byKey(const ValueKey('preset-prompt-detail-pane'));
    final deleteButton = find.descendant(
      of: detailPane,
      matching: find.widgetWithText(OutlinedButton, '删除当前条目'),
    );

    expect(
      find.descendant(
        of: detailPane,
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );

    final contentEditor = tester.widget<EditableText>(
      find.descendant(
        of: presetPromptContentField(),
        matching: find.byType(EditableText),
      ),
    );
    expect(contentEditor.expands, isTrue);
    expect(contentEditor.maxLines, isNull);
    expect(contentEditor.minLines, isNull);
    expect(deleteButton.hitTestable(), findsOneWidget);
  });

  testWidgets(
    'settings screen supports template prompt CRUD flows',
    (tester) async {
      final preferences = await createEmptyPreferences();

      await pumpSettingsScreen(tester, preferences: preferences);

      expect(find.text('还没有模板提示词'), findsOneWidget);

      await tester.tap(find.text('新增模板提示词'));
      await tester.pumpAndSettle();

      await tester.enterText(templatePromptTitleField(), '翻译模板');
      await tester.enterText(
        templatePromptContentField(),
        '请把{{正文}}翻译成{{目标语言}}。',
      );
      await tester.pumpAndSettle();

      expect(find.text('正文 使用聊天页主输入框提供内容，不单独设置默认值。'), findsOneWidget);

      await tester.enterText(templatePromptVariableField('目标语言'), '英文');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('翻译模板'), findsWidgets);
      expect(find.textContaining('共 2 个变量'), findsOneWidget);

      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(templatePromptTitleField()).controller?.text,
        '翻译模板',
      );
      expect(
        tester.widget<TextFormField>(
          templatePromptContentField(),
        ).controller?.text,
        '请把{{正文}}翻译成{{目标语言}}。',
      );
      expect(
        tester.widget<TextFormField>(
          templatePromptVariableField('目标语言'),
        ).controller?.text,
        '英文',
      );
      await tester.enterText(templatePromptTitleField(), '翻译模板 v2');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('翻译模板 v2'), findsWidgets);

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(find.text('还没有模板提示词'), findsOneWidget);
    },
  );

  testWidgets(
    'template prompt variable reconcile uses throttle and stays consistent',
    (tester) async {
      final preferences = await createEmptyPreferences();
      await pumpSettingsScreen(tester, preferences: preferences);

      await tester.tap(find.text('新增模板提示词'));
      await tester.pumpAndSettle();

      await tester.enterText(templatePromptTitleField(), '调度测试');
      await tester.enterText(templatePromptContentField(), '请处理{{变量A}}。');
      await tester.pump();
      expect(find.text('变量A'), findsOneWidget);

      await tester.enterText(templatePromptContentField(), '请处理{{变量B}}。');
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('变量A'), findsOneWidget);
      expect(find.text('变量B'), findsNothing);

      await tester.pump(const Duration(milliseconds: 140));
      expect(find.text('变量A'), findsNothing);
      expect(find.text('变量B'), findsOneWidget);
    },
  );

  testWidgets('settings screen supports memory prompt CRUD with persistence', (
    tester,
  ) async {
    final preferences = await createEmptyPreferences();

    await pumpSettingsScreen(tester, preferences: preferences);

    expect(find.text('还没有记忆总结提示词'), findsOneWidget);

    await tester.tap(find.text('新增记忆提示词'));
    await tester.pumpAndSettle();

    await tester.enterText(memoryPromptNameField(), '研发任务总结');
    await tester.enterText(
      memoryPromptContentField(),
      '请总结当前研发任务中的决定、约束与待办。',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('研发任务总结'), findsWidgets);

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(memoryPromptNameField()).controller?.text,
      '研发任务总结',
    );
    expect(
      tester.widget<TextFormField>(memoryPromptContentField()).controller?.text,
      '请总结当前研发任务中的决定、约束与待办。',
    );
    await tester.enterText(memoryPromptNameField(), '研发任务总结 v2');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('研发任务总结 v2'), findsWidgets);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('还没有记忆总结提示词'), findsOneWidget);
  });

  testWidgets(
    'settings card grid arranges equal-width columns on wide layout',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 960,
                child: SettingsCardGrid(
                  minItemWidth: 100,
                  children: [
                    Container(
                      key: ValueKey('grid-card-short'),
                      color: Colors.red,
                      child: SizedBox(height: 80),
                    ),
                    Container(
                      key: ValueKey('grid-card-tall'),
                      color: Colors.green,
                      child: SizedBox(height: 180),
                    ),
                    Container(
                      key: ValueKey('grid-card-medium'),
                      color: Colors.blue,
                      child: SizedBox(height: 120),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final shortRect = tester.getRect(
        find.byKey(const ValueKey('grid-card-short')),
      );
      final tallRect = tester.getRect(
        find.byKey(const ValueKey('grid-card-tall')),
      );
      final mediumRect = tester.getRect(
        find.byKey(const ValueKey('grid-card-medium')),
      );

      expect(shortRect.top, moreOrLessEquals(tallRect.top));
      expect(mediumRect.top, moreOrLessEquals(tallRect.top));
      expect(shortRect.width, moreOrLessEquals(tallRect.width));
      expect(mediumRect.width, moreOrLessEquals(tallRect.width));
      expect(shortRect.left, lessThan(tallRect.left));
      expect(tallRect.left, lessThan(mediumRect.left));
    },
  );
}

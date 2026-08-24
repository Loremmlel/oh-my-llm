import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/providers/notification_bubble_provider.dart';
import 'package:oh_my_llm/features/settings/application/preferences/settings_tab_preferences.dart';
import 'package:oh_my_llm/features/settings/application/ports/system_notification_settings.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/shared/settings_section_card.dart';

import '../../../../helpers/fixtures.dart';
import 'settings_screen_test_helpers.dart';

/// 其它 tab 在设置页 TabBar 中的固定下标。
const _otherTabIndex = 5;

Finder _systemNotificationCard() => find.ancestor(
  of: find.text('系统通知'),
  matching: find.byType(SettingsSectionCard),
);

/// 创建内存库与带当前版本号的 tab 偏好种子：tab 索引必须连同
/// [settingsTabVersionKey] 一起写入，否则存储值按 legacy 版本迁移会把
/// 索引 5 换位成 4（输出处理），导致落错标签页。
Future<(AppDatabase, SharedPreferences)> _createEnvironment() async {
  final database = AppDatabase.inMemory();
  addTearDown(database.close);
  final preferences = await TestFixtures.seedPreferences(database: database);
  await preferences.setInt(settingsTabVersionKey, settingsCurrentTabVersion);
  return (database, preferences);
}

/// 挂载设置页并直接落在其它 tab；返回注入的系统通知端口 Fake。
Future<FakeSystemNotificationSettings> _pumpOtherTab(
  WidgetTester tester, {
  SystemNotificationStatus status = SystemNotificationStatus.enabled,
  bool openSettingsResult = true,
}) async {
  final (database, preferences) = await _createEnvironment();
  final fake = FakeSystemNotificationSettings(
    status: status,
    openSettingsResult: openSettingsResult,
  );
  await pumpSettingsScreen(
    tester,
    preferences: preferences,
    database: database,
    initialTabIndex: _otherTabIndex,
    systemNotificationSettings: fake,
  );
  // 端口应答是同步完成的 Future：一帧后状态落地。
  await tester.pump();
  return fake;
}

void registerSettingsScreenSystemNotificationTests() {
  testWidgets('读取状态时显示流畅加载提示', (tester) async {
    final (database, preferences) = await _createEnvironment();
    final fake = FakeSystemNotificationSettings(
      status: SystemNotificationStatus.enabled,
    )..statusGate = Completer<void>();
    await pumpSettingsScreen(
      tester,
      preferences: preferences,
      database: database,
      initialTabIndex: _otherTabIndex,
      systemNotificationSettings: fake,
    );

    expect(_systemNotificationCard(), findsOneWidget);
    expect(find.text('正在读取系统通知状态'), findsOneWidget);
    expect(
      find.descendant(
        of: _systemNotificationCard(),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    // 查询未落地前不得提前渲染任何确定状态。
    expect(find.text('系统通知已开启'), findsNothing);

    // 数据返回后加载提示让位于具体状态。
    fake.statusGate!.complete();
    await tester.pump();
    expect(find.text('正在读取系统通知状态'), findsNothing);
    expect(find.text('系统通知已开启'), findsOneWidget);
  });

  testWidgets('系统通知开启时显示已开启和设置按钮', (tester) async {
    await _pumpOtherTab(tester, status: SystemNotificationStatus.enabled);

    expect(find.text('系统通知已开启'), findsOneWidget);
    expect(find.text('打开系统通知设置'), findsOneWidget);
  });

  testWidgets('系统通知关闭时显示系统已关闭和设置按钮', (tester) async {
    await _pumpOtherTab(tester, status: SystemNotificationStatus.disabled);

    expect(find.text('系统通知已关闭'), findsOneWidget);
    expect(find.text('打开系统通知设置'), findsOneWidget);
  });

  testWidgets('Windows 功能可用时不显示已开启断言', (tester) async {
    await _pumpOtherTab(tester, status: SystemNotificationStatus.available);

    expect(find.text('系统通知功能可用，具体横幅和声音由 Windows 管理'), findsOneWidget);
    // available 只代表功能可用，不得伪装成系统开关已开启。
    expect(find.text('系统通知已开启'), findsNothing);
  });

  testWidgets('不可用时显示不可用且禁用按钮', (tester) async {
    final fake = await _pumpOtherTab(
      tester,
      status: SystemNotificationStatus.unavailable,
    );

    expect(find.text('当前平台无法使用系统通知'), findsOneWidget);

    await tester.ensureVisible(find.text('打开系统通知设置'));
    await tester.tap(find.text('打开系统通知设置'));
    await tester.pump();

    // 按钮禁用：点击不触发任何平台调用。
    expect(fake.openSettingsCallCount, 0);
  });

  testWidgets('点击设置按钮只调用 application controller', (tester) async {
    final fake = await _pumpOtherTab(tester);

    await tester.ensureVisible(find.text('打开系统通知设置'));
    await tester.tap(find.text('打开系统通知设置'));
    await tester.pump();

    expect(fake.openSettingsCallCount, 1);
    // 点击路径只经过 controller 的 openSettings，不触发额外状态查询。
    expect(fake.getStatusCallCount, 1);
    expect(find.text('无法打开系统通知设置'), findsNothing);
  });

  testWidgets('打开失败时显示非阻塞错误气泡', (tester) async {
    final fake = await _pumpOtherTab(tester, openSettingsResult: false);

    await tester.ensureVisible(find.text('打开系统通知设置'));
    await tester.tap(find.text('打开系统通知设置'));
    await tester.pump();
    // 气泡经 post-frame 回调插入 AnimatedList，第二帧后才进入树。
    await tester.pump();

    expect(fake.openSettingsCallCount, 1);
    expect(find.text('无法打开系统通知设置'), findsOneWidget);
    // 非阻塞：失败不弹对话框，页面保持可浏览。
    expect(find.byType(AlertDialog), findsNothing);

    // 显式关闭气泡收尾：自动消失靠真实 Timer，跨用例残留会让测试失败；
    // 显式 dismiss 不依赖气泡默认停留时长的实现细节。
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    container
        .read(notificationBubblesProvider.notifier)
        .dismiss(container.read(notificationBubblesProvider).single.id);
    await tester.pump();
  });

  testWidgets('应用恢复前台时刷新状态', (tester) async {
    final fake = await _pumpOtherTab(tester);
    expect(fake.getStatusCallCount, 1);

    // 用户从系统设置页改完开关返回应用：inactive -> resumed 触发重新查询
    // （AppLifecycleListener 不接受 hidden 直跳 resumed，合法回前台路径经
    // inactive）；addTearDown 保证用例中途失败时生命周期状态也复位。
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(fake.getStatusCallCount, 2);
  });

  testWidgets('通知设置不出现应用内开关', (tester) async {
    await _pumpOtherTab(tester);

    final card = _systemNotificationCard();
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.byType(SwitchListTile)),
      findsNothing,
    );
    expect(
      find.descendant(of: card, matching: find.byType(Switch)),
      findsNothing,
    );
  });
}

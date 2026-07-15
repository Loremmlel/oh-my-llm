import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/sync/application/network_interface_provider.dart';
import 'package:oh_my_llm/features/sync/domain/models/network_interface_info.dart';
import 'package:oh_my_llm/features/sync/presentation/widgets/interface_selector.dart';

Future<void> _pumpSelector(
  WidgetTester tester, {
  required SharedPreferences preferences,
  required List<NetworkInterfaceInfo> interfaces,
}) async {
  tester.view.physicalSize = const Size(1440, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        availableInterfacesProvider.overrideWith(
          (ref) async => interfaces,
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: InterfaceSelector(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('InterfaceSelector', () {
    late SharedPreferences preferences;
    const fakeInterface = NetworkInterfaceInfo(name: 'wlan0', ip: '10.214.98.86');

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
    });

    testWidgets('渲染 /8 /16 /24 三个 SegmentedButton 选项', (tester) async {
      await _pumpSelector(
        tester,
        preferences: preferences,
        interfaces: const [fakeInterface],
      );

      expect(find.text('/8'), findsOneWidget);
      expect(find.text('/16'), findsOneWidget);
      expect(find.text('/24'), findsOneWidget);
    });

    testWidgets('默认选中 /24', (tester) async {
      await _pumpSelector(
        tester,
        preferences: preferences,
        interfaces: const [fakeInterface],
      );

      // /24 模式下广播地址以 .255 结尾，间接验证 /24 被默认选中
      expect(find.textContaining('10.214.98.255'), findsOneWidget);
    });

    testWidgets('SharedPreferences 存 16 时默认选中 /16', (tester) async {
      SharedPreferences.setMockInitialValues({
        'sync.broadcast_prefix_length': 16,
      });
      preferences = await SharedPreferences.getInstance();

      await _pumpSelector(
        tester,
        preferences: preferences,
        interfaces: const [fakeInterface],
      );

      // /16 模式下广播地址为 10.214.255.255，间接验证 /16 被选中
      expect(find.textContaining('10.214.255.255'), findsOneWidget);
    });

    testWidgets('点击 /16 后 UI 选中 /16', (tester) async {
      await _pumpSelector(
        tester,
        preferences: preferences,
        interfaces: const [fakeInterface],
      );

      // 默认 /24 -> 广播地址 10.214.98.255
      expect(find.textContaining('10.214.98.255'), findsOneWidget);

      await tester.tap(find.text('/16'));
      await tester.pump();

      // 切换到 /16 后广播地址变为 10.214.255.255
      expect(find.textContaining('10.214.255.255'), findsOneWidget);
    });

    testWidgets('展示当前计算的广播地址：/24 模式下 10.214.98.86 → 10.214.98.255',
        (tester) async {
      // 这正是主人手机热点场景的修复点
      await _pumpSelector(
        tester,
        preferences: preferences,
        interfaces: const [fakeInterface],
      );

      expect(find.textContaining('10.214.98.255'), findsOneWidget);
      expect(find.textContaining('10.255.255.255'), findsNothing);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/composition/cross_feature_bindings.dart';
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
        ...appCompositionOverrides(),
        sharedPreferencesProvider.overrideWithValue(preferences),
        availableInterfacesProvider.overrideWith((ref) async => interfaces),
      ],
      child: const MaterialApp(home: Scaffold(body: InterfaceSelector())),
    ),
  );
  // 接口列表是同步返回的 Future Provider，异步解析后单帧渲染即可
  await tester.pump();
}

void main() {
  group('InterfaceSelector', () {
    late SharedPreferences preferences;
    const fakeInterface = NetworkInterfaceInfo(
      name: 'wlan0',
      ip: '10.214.98.86',
    );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
    });

    testWidgets('渲染 /8 /16 /24 选项并默认选中 /24 广播地址', (tester) async {
      await _pumpSelector(
        tester,
        preferences: preferences,
        interfaces: const [fakeInterface],
      );

      expect(find.text('/8'), findsOneWidget);
      expect(find.text('/16'), findsOneWidget);
      expect(find.text('/24'), findsOneWidget);
      // /24 模式下广播地址以 .255 结尾，间接验证 /24 被默认选中；
      // 未选中的 /8 广播地址不应出现
      expect(find.textContaining('10.214.98.255'), findsOneWidget);
      // 主人手机热点场景的修复点：/8 广播地址（10.255.255.255）不得出现
      expect(find.textContaining('10.255.255.255'), findsNothing);
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

    testWidgets('点击 /16 后可见广播地址从 /24 切换到 /16', (tester) async {
      await _pumpSelector(
        tester,
        preferences: preferences,
        interfaces: const [fakeInterface],
      );

      // 默认 /24 -> 广播地址 10.214.98.255
      expect(find.textContaining('10.214.98.255'), findsOneWidget);

      await tester.tap(find.text('/16'));
      await tester.pump();

      // 切换后原 /24 地址消失，改为 /16 广播地址 10.214.255.255
      expect(find.textContaining('10.214.98.255'), findsNothing);
      expect(find.textContaining('10.214.255.255'), findsOneWidget);
    });
  });
}

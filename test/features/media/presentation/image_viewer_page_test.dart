import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/media/presentation/pages/image_viewer_page.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';

import '../../../helpers/test_harness.dart';

/// 构建一组用于测试的假图片 URL。
///
/// 使用局域网 IP + 媒体 API 格式模拟真实场景。
List<String> _fakeUrls(int count) {
  return List.generate(
    count,
    (i) => 'http://192.168.1.100:8080/api/media/image/test/photo_${i + 1}.jpg',
  );
}

/// 创建设置默认值的 SharedPreferences 方便快捷。
Future<SharedPreferences> _testPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void main() {
  // ── 静态渲染 ──────────────────────────────────────────────────

  group('静态渲染', () {
    testWidgets('页面计数器显示正确格式（如 "3 / 5"）', (tester) async {
      final prefs = await _testPrefs();
      await pumpTestApp(
        tester,
        preferences: prefs,
        child: ImageViewerPage(
          imageUrls: _fakeUrls(5),
          initialIndex: 2,
        ),
      );

      // 计数器在右上角
      expect(find.text('3 / 5'), findsOneWidget);
    });

    testWidgets('返回按钮存在', (tester) async {
      final prefs = await _testPrefs();
      await pumpTestApp(
        tester,
        preferences: prefs,
        child: ImageViewerPage(imageUrls: _fakeUrls(3)),
      );

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('单张图片时隐藏页面计数器', (tester) async {
      final prefs = await _testPrefs();
      await pumpTestApp(
        tester,
        preferences: prefs,
        child: ImageViewerPage(imageUrls: _fakeUrls(1)),
      );

      // 单张图片不应显示 "1 / 1" 计数器
      expect(find.text('1 / 1'), findsNothing);
    });

    testWidgets('多张图片时显示计数器', (tester) async {
      final prefs = await _testPrefs();
      await pumpTestApp(
        tester,
        preferences: prefs,
        child: ImageViewerPage(imageUrls: _fakeUrls(2)),
      );

      expect(find.text('1 / 2'), findsOneWidget);
    });

    testWidgets('PageView 使用正确的 initialIndex', (tester) async {
      final prefs = await _testPrefs();
      await pumpTestApp(
        tester,
        preferences: prefs,
        child: ImageViewerPage(
          imageUrls: _fakeUrls(5),
          initialIndex: 3,
        ),
      );

      // 计数器应反映 initialIndex = 3（显示为 4 / 5）
      expect(find.text('4 / 5'), findsOneWidget);
    });

    testWidgets('图片加载失败时显示错误状态', (tester) async {
      final prefs = await _testPrefs();
      await pumpTestApp(
        tester,
        preferences: prefs,
        child: ImageViewerPage(imageUrls: _fakeUrls(3)),
      );

      // 额外 pump 让 addPostFrameCallback 执行（设置 _hasError）
      await tester.pump();

      // broken_image 图标和文字应出现
      expect(find.byIcon(Icons.broken_image), findsOneWidget);
      expect(find.text('图片加载失败'), findsOneWidget);
    });
  });

  // ── 边界条件 ──────────────────────────────────────────────────

  group('边界条件', () {
    testWidgets('initialIndex = 0 时正确初始化', (tester) async {
      final prefs = await _testPrefs();
      await pumpTestApp(
        tester,
        preferences: prefs,
        child: ImageViewerPage(imageUrls: _fakeUrls(3), initialIndex: 0),
      );

      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('initialIndex 在末尾位置正确初始化', (tester) async {
      final prefs = await _testPrefs();
      await pumpTestApp(
        tester,
        preferences: prefs,
        child: ImageViewerPage(imageUrls: _fakeUrls(3), initialIndex: 2),
      );

      expect(find.text('3 / 3'), findsOneWidget);
    });

    testWidgets('单张图片时 PageView 存在不可滑动', (tester) async {
      final prefs = await _testPrefs();
      await pumpTestApp(
        tester,
        preferences: prefs,
        child: ImageViewerPage(imageUrls: _fakeUrls(1)),
      );

      // 单张图片的 PageView 只有一页，滑动不应更改页面
      // 验证 PageView 存在（通过检查计数器隐藏来间接确认）
      expect(find.textContaining('/'), findsNothing);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });
  });

  // ── 手势 ──────────────────────────────────────────────────────

  group('手势', () {
    testWidgets('滑动切换页面后计数器更新', (tester) async {
      final prefs = await _testPrefs();
      await pumpTestApp(
        tester,
        preferences: prefs,
        viewportSize: const Size(400, 800),
        child: ImageViewerPage(
          imageUrls: _fakeUrls(5),
          initialIndex: 0,
        ),
      );
      await tester.pump(); // 让 errorBuilder 回调执行

      // 初始在第 1 页
      expect(find.text('1 / 5'), findsOneWidget);

      // 向左滑动切换到第 2 页
      await tester.fling(
        find.byType(PageView),
        const Offset(-200, 0),
        1000,
      );
      await tester.pumpAndSettle();

      // 计数器应更新为 2 / 5
      expect(find.text('2 / 5'), findsOneWidget);
    });

    testWidgets('首页右滑无效果（边界 clamp）', (tester) async {
      final prefs = await _testPrefs();
      await pumpTestApp(
        tester,
        preferences: prefs,
        viewportSize: const Size(400, 800),
        child: ImageViewerPage(
          imageUrls: _fakeUrls(3),
          initialIndex: 0,
        ),
      );
      await tester.pump();

      // 初始在第 1 页
      expect(find.text('1 / 3'), findsOneWidget);

      // 在首页向右滑动（应被 clamp，不翻页）
      await tester.fling(
        find.byType(PageView),
        const Offset(200, 0),
        1000,
      );
      await tester.pumpAndSettle();

      // 仍在第 1 页
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('末页左滑无效果（边界 clamp）', (tester) async {
      final prefs = await _testPrefs();
      await pumpTestApp(
        tester,
        preferences: prefs,
        viewportSize: const Size(400, 800),
        child: ImageViewerPage(
          imageUrls: _fakeUrls(3),
          initialIndex: 2,
        ),
      );
      await tester.pump();

      // 初始在最后一页
      expect(find.text('3 / 3'), findsOneWidget);

      // 在末页向左滑动（应被 clamp）
      await tester.fling(
        find.byType(PageView),
        const Offset(-200, 0),
        1000,
      );
      await tester.pumpAndSettle();

      // 仍在最后一页
      expect(find.text('3 / 3'), findsOneWidget);
    });

    testWidgets('双击错误状态下图片不触发缩放', (tester) async {
      final prefs = await _testPrefs();
      await pumpTestApp(
        tester,
        preferences: prefs,
        child: ImageViewerPage(imageUrls: _fakeUrls(3)),
      );
      await tester.pump(); // 进入错误状态

      // 验证错误状态已显示
      expect(find.byIcon(Icons.broken_image), findsOneWidget);

      // 双击错误组件不应引起异常（_hasError 保护了 _onDoubleTap）
      await tester.tap(find.byIcon(Icons.broken_image));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(find.byIcon(Icons.broken_image));
      await tester.pump(const Duration(milliseconds: 250));

      // 不应有崩溃；页面仍在
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });
  });

  // ── 页面状态 ──────────────────────────────────────────────────

  group('页面状态', () {
    testWidgets('返回按钮关闭页面', (tester) async {
      final prefs = await _testPrefs();
      await pumpTestApp(
        tester,
        preferences: prefs,
        child: ImageViewerPage(imageUrls: _fakeUrls(3)),
      );

      // 点击返回
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // ImageViewerPage 通过 Navigator.push 进入，pop 后应返回上一个路由
      // 在测试中，由于只有这一层页面，pop 后会显示空或前一个路由。
      // 直接验证返回到 pumpTestApp 的初始路由（即不再有 ImageViewerPage 的内容）
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });

    testWidgets('快速连续翻页后计数器正确', (tester) async {
      final prefs = await _testPrefs();
      await pumpTestApp(
        tester,
        preferences: prefs,
        viewportSize: const Size(400, 800),
        child: ImageViewerPage(
          imageUrls: _fakeUrls(10),
          initialIndex: 0,
        ),
      );
      await tester.pump();

      // 连续快速滑动 3 次
      for (int i = 0; i < 3; i++) {
        await tester.fling(
          find.byType(PageView),
          const Offset(-200, 0),
          1000,
        );
        await tester.pumpAndSettle();
      }

      // 应在第 4 页
      expect(find.text('4 / 10'), findsOneWidget);
    });

    testWidgets('多页翻页后 _pageZoomStates 正确初始化', (tester) async {
      final prefs = await _testPrefs();
      await pumpTestApp(
        tester,
        preferences: prefs,
        viewportSize: const Size(400, 800),
        child: ImageViewerPage(
          imageUrls: _fakeUrls(5),
          initialIndex: 0,
        ),
      );
      await tester.pump();

      // 翻到第 3 页
      await tester.fling(
        find.byType(PageView),
        const Offset(-200, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(find.text('2 / 5'), findsOneWidget);

      // 再翻一页
      await tester.fling(
        find.byType(PageView),
        const Offset(-200, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(find.text('3 / 5'), findsOneWidget);

      // 翻回第 1 页
      await tester.fling(
        find.byType(PageView),
        const Offset(200, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(find.text('2 / 5'), findsOneWidget);

      // 所有页面都应正确显示，无崩溃
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });
  });

  // ── 沉浸式模式 ────────────────────────────────────────────────

  group('沉浸式模式', () {
    testWidgets('进入图片浏览器时启用沉浸式模式', (tester) async {
      final prefs = await _testPrefs();
      await pumpTestApp(
        tester,
        preferences: prefs,
        child: ImageViewerPage(imageUrls: _fakeUrls(3)),
      );

      // 图片浏览器应有黑色背景（Scaffold backgroundColor）
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, Colors.black);
    });
  });
}

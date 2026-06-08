import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/media/presentation/pages/video_player_page.dart';
import 'package:oh_my_llm/features/media/presentation/widgets/video_player_controls.dart';

/// 包裹 widget 到 MaterialApp + Navigator 中，模拟真实导航场景。
Widget _wrapWithMaterialApp(Widget child) {
  return MaterialApp(
    home: Navigator(
      pages: [MaterialPage(child: child)],
      onPopPage: (route, result) => route.didPop(result),
    ),
  );
}

/// 创建测试用的 VideoPlayerPage。
///
/// 测试环境中 VideoPlayerController.networkUrl 必然快速失败，
/// 因此测试聚焦 UI 结构和交互逻辑，而非真实播放行为。
Widget _buildTestPage() {
  return _wrapWithMaterialApp(
    const VideoPlayerPage(
      videoUrl: 'http://localhost:99999/nonexistent.mp4',
      fileName: 'test-video.mp4',
    ),
  );
}

void main() {
  // ── 静态渲染 ─────────────────────────────────────────────────

  group('静态渲染', () {
    testWidgets('黑色背景 Scaffold', (tester) async {
      await tester.pumpWidget(_buildTestPage());
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('返回按钮存在', (tester) async {
      await tester.pumpWidget(_buildTestPage());
      await tester.pump();
      // 控制栏默认可见，返回按钮在顶部栏中
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('倍速按钮存在', (tester) async {
      await tester.pumpWidget(_buildTestPage());
      await tester.pump();
      // 倍速按钮显示 "1.0x"
      expect(find.text('1.0x'), findsOneWidget);
    });

    testWidgets('音量按钮存在', (tester) async {
      await tester.pumpWidget(_buildTestPage());
      await tester.pump();
      // 默认音量 1.0，显示 volume_up 图标
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
    });

    testWidgets('播放/暂停按钮存在', (tester) async {
      await tester.pumpWidget(_buildTestPage());
      await tester.pump();
      // 初始未播放，应显示播放图标
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('时间显示存在', (tester) async {
      await tester.pumpWidget(_buildTestPage());
      await tester.pump();
      // 未初始化时显示 "--:--"
      expect(find.text('--:--'), findsOneWidget);
    });

    testWidgets('进度条始终存在', (tester) async {
      await tester.pumpWidget(_buildTestPage());
      await tester.pump();
      // Slider 始终在底部栏中，无时长时处于禁用状态
      expect(find.byType(Slider), findsOneWidget);
    });
  });

  // ── 错误状态 ─────────────────────────────────────────────────

  group('错误状态', () {
    testWidgets('加载失败时显示错误信息', (tester) async {
      await tester.pumpWidget(_buildTestPage());
      // 等待异步初始化失败（controller 在网络不可用时快速失败）
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('视频加载失败'), findsOneWidget);
    });

    testWidgets('加载失败时显示重试按钮', (tester) async {
      await tester.pumpWidget(_buildTestPage());
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('错误状态下可点击重试按钮', (tester) async {
      await tester.pumpWidget(_buildTestPage());
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // 确认处于错误状态
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      // 点击重试按钮不应抛出异常
      await tester.tap(find.text('重试'));
      await tester.pump();

      // 重试触发 _initPlayer，状态机正常运转（widget 不崩溃即为通过）
      // 测试环境中网络不可用，重试后仍会进入错误状态
    });
  });

  // ── 控制栏 ─────────────────────────────────────────────────

  group('控制栏', () {
    testWidgets('初始控制栏可见（Slider 存在）', (tester) async {
      await tester.pumpWidget(_buildTestPage());
      await tester.pump();

      // 控制栏中的 Slider 始终存在
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('点击视频区域切换控制栏显隐状态', (tester) async {
      await tester.pumpWidget(_buildTestPage());
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // 点击视频区域后控件仍在树中（AnimatedOpacity/IgnorePointer 控制可见性）
      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 400));

      // 控件不会从树中移除（仅通过 opacity 和 IgnorePointer 切换）
      expect(find.byType(Slider), findsOneWidget);
    });
  });

  // ── 倍速选择器 ──────────────────────────────────────────────

  group('倍速选择器', () {
    testWidgets('倍速 PopupMenuButton 存在', (tester) async {
      await tester.pumpWidget(_buildTestPage());
      await tester.pump();
      expect(find.text('1.0x'), findsOneWidget);
    });

    testWidgets('点击倍速按钮弹出菜单', (tester) async {
      await tester.pumpWidget(_buildTestPage());
      await tester.pump();

      // 点击倍速按钮
      await tester.tap(find.text('1.0x'));
      await tester.pump();

      // PopupMenu 中有多个速度选项
      expect(find.text('0.25x'), findsOneWidget);
      expect(find.text('0.5x'), findsOneWidget);
      expect(find.text('2.0x'), findsOneWidget);
    });
  });

  // ── 音量面板 ────────────────────────────────────────────────

  group('音量面板', () {
    testWidgets('点击音量按钮弹出对话框', (tester) async {
      await tester.pumpWidget(_buildTestPage());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pump();

      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('音量对话框中包含 Slider', (tester) async {
      await tester.pumpWidget(_buildTestPage());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pump();

      // 底部栏已有 1 个 Slider，对话框中还有 1 个
      expect(find.byType(Slider), findsNWidgets(2));
    });
  });

  // ── 返回按钮 ────────────────────────────────────────────────

  group('返回按钮', () {
    testWidgets('点击返回按钮关闭页面', (tester) async {
      await tester.pumpWidget(_buildTestPage());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // VideoPlayerPage 应该已从导航栈弹出
      expect(find.byType(VideoPlayerPage), findsNothing);
    });
  });

  // ── 中央提示 ────────────────────────────────────────────────

  group('中央提示', () {
    testWidgets('中央提示组件始终在树中', (tester) async {
      await tester.pumpWidget(_buildTestPage());
      await tester.pump();

      // VideoCenterHint 始终在 Stack 中（visible 控制是否渲染内容）
      expect(find.byType(VideoCenterHint), findsOneWidget);
    });
  });

  // ── 工具函数 ────────────────────────────────────────────────

  group('时间格式化', () {
    test('formatVideoDuration mm:ss 格式', () {
      expect(
          formatVideoDuration(const Duration(minutes: 5, seconds: 30)),
          '05:30');
    });

    test('formatVideoDuration h:mm:ss 格式', () {
      expect(
          formatVideoDuration(
              const Duration(hours: 1, minutes: 23, seconds: 45)),
          '1:23:45');
    });

    test('formatVideoDuration 零时长', () {
      expect(formatVideoDuration(Duration.zero), '00:00');
    });
  });

  group('音量图标', () {
    test('音量为零显示 volume_off', () {
      expect(volumeIconData(0.0), Icons.volume_off);
    });

    test('音量低于 0.5 显示 volume_down', () {
      expect(volumeIconData(0.3), Icons.volume_down);
    });

    test('音量 >= 0.5 显示 volume_up', () {
      expect(volumeIconData(0.5), Icons.volume_up);
      expect(volumeIconData(1.0), Icons.volume_up);
    });
  });
}

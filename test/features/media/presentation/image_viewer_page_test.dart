import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/media/application/media_library_session_controller.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource_request.dart';
import 'package:oh_my_llm/features/media/presentation/pages/image_viewer_page.dart';

import '../../../helpers/test_harness.dart';
import '../../../helpers/widget_test_animation.dart';
import '../helpers/fake_media_library.dart';
import '../helpers/media_test_helpers.dart';

/// 构建一组用于测试的图片懒资源请求。
List<MediaAssetRequest> _imageRequests(int count) {
  return List.generate(
    count,
    (i) => MediaAssetRequest(
      kind: MediaAssetKind.image,
      relativePath: '/test/photo_${i + 1}.jpg',
    ),
  );
}

/// 为全部请求配置远端资源结果的库；测试环境 mock HTTP 恒返回 400，
/// 解码失败经 errorBuilder 呈现 broken-image 状态。
FakeMediaLibrary _libraryWithImages(int count) {
  final library = FakeMediaLibrary();
  for (final request in _imageRequests(count)) {
    library.assetResults[request] = NetworkMediaResource(
      Uri.parse(
        'http://192.168.1.100:8080/api/media/image${request.relativePath}',
      ),
    );
  }
  return library;
}

/// 创建设置默认值的 SharedPreferences 方便快捷。
Future<SharedPreferences> _testPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void main() {
  // ── 静态渲染 ──────────────────────────────────────────────────

  group('静态渲染', () {
    testWidgets('initialIndex 指定起始页，计数器显示 3 / 5', (tester) async {
      final prefs = await _testPrefs();
      await pumpTestApp(
        tester,
        preferences: prefs,
        extraOverrides: [
          mediaLibrarySessionProvider.overrideWith(
            () => PreActivatedMediaLibrarySessionController(
              _libraryWithImages(5),
            ),
          ),
        ],
        child: ImageViewerPage(
          imageRequests: _imageRequests(5),
          initialIndex: 2,
        ),
      );

      // 计数器格式与 initialIndex 生效一次覆盖：显示 "3 / 5"
      expect(find.text('3 / 5'), findsOneWidget);
    });

    testWidgets('单张图片时隐藏页面计数器', (tester) async {
      final prefs = await _testPrefs();
      await pumpTestApp(
        tester,
        preferences: prefs,
        extraOverrides: [
          mediaLibrarySessionProvider.overrideWith(
            () => PreActivatedMediaLibrarySessionController(
              _libraryWithImages(1),
            ),
          ),
        ],
        child: ImageViewerPage(imageRequests: _imageRequests(1)),
      );

      // 单张图片不应显示 "1 / 1" 计数器
      expect(find.text('1 / 1'), findsNothing);
    });

    testWidgets('图片加载失败时显示错误状态', (tester) async {
      final prefs = await _testPrefs();
      await pumpTestApp(
        tester,
        preferences: prefs,
        extraOverrides: [
          mediaLibrarySessionProvider.overrideWith(
            () => PreActivatedMediaLibrarySessionController(
              _libraryWithImages(3),
            ),
          ),
        ],
        child: ImageViewerPage(imageRequests: _imageRequests(3)),
      );

      // 帧 1：资源解析完成并渲染网络图；帧 2：mock HTTP 400 触发解码
      // 失败，errorBuilder 的 postFrame 回调把错误状态置位
      await tester.pump();
      await tester.pump();

      // broken_image 图标和文字应出现
      expect(find.byIcon(Icons.broken_image), findsOneWidget);
      expect(find.text('图片加载失败'), findsOneWidget);
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
        extraOverrides: [
          mediaLibrarySessionProvider.overrideWith(
            () => PreActivatedMediaLibrarySessionController(
              _libraryWithImages(5),
            ),
          ),
        ],
        child: ImageViewerPage(
          imageRequests: _imageRequests(5),
          initialIndex: 0,
        ),
      );
      await tester.pump(); // 让资源解析完成并渲染网络图

      // 初始在第 1 页
      expect(find.text('1 / 5'), findsOneWidget);

      // 向左滑动切换到第 2 页
      await tester.fling(find.byType(PageView), const Offset(-200, 0), 1000);
      await settleScrollMotion(tester);

      // 计数器应更新为 2 / 5
      expect(find.text('2 / 5'), findsOneWidget);
    });
  });

  // ── 页面状态 ──────────────────────────────────────────────────

  group('页面状态', () {
    testWidgets('返回按钮关闭页面', (tester) async {
      final prefs = await _testPrefs();
      await pumpTestApp(
        tester,
        preferences: prefs,
        extraOverrides: [
          mediaLibrarySessionProvider.overrideWith(
            () => PreActivatedMediaLibrarySessionController(
              _libraryWithImages(3),
            ),
          ),
        ],
        child: ImageViewerPage(imageRequests: _imageRequests(3)),
      );

      // 点击返回
      await tester.tap(find.byIcon(Icons.arrow_back));
      await settleRouteTransition(tester);

      // ImageViewerPage 是路由承载的页面，pop 后应返回父页面。
      // 在测试中作为唯一页面，pop 后不再有 ImageViewerPage 的内容。
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/constants/app_layout_density.dart';
import 'package:oh_my_llm/features/media/application/media_grid_density_controller.dart';
import 'package:oh_my_llm/features/media/application/media_library_session_controller.dart';
import 'package:oh_my_llm/features/media/application/models/media_resource_request.dart';
import 'package:oh_my_llm/features/media/presentation/widgets/media_grid_view.dart';
import 'package:oh_my_llm/features/media/presentation/widgets/media_path_bar.dart';

import '../../../../helpers/test_harness.dart';
import '../../helpers/fake_media_library.dart';
import '../../helpers/media_test_helpers.dart';

/// 用内存 SharedPreferences（可选预置键）创建偏好实例。
Future<SharedPreferences> _testPrefs([
  Map<String, Object> seed = const {},
]) async {
  SharedPreferences.setMockInitialValues(seed);
  return SharedPreferences.getInstance();
}

FileItem _file(String path, {bool hasThumbnail = false, int sizeBytes = 1}) =>
    FileItem(
      name: path.split('/').last,
      isDirectory: false,
      sizeBytes: sizeBytes,
      relativePath: path,
      hasThumbnail: hasThumbnail,
    );

FileItem _dir(String path) => FileItem(
  name: path.split('/').last,
  isDirectory: true,
  sizeBytes: 0,
  relativePath: path,
);

/// 渲染「路径栏 + 媒体网格」，注入预激活媒体会话与 Fake 库。
///
/// 直接以 [MediaGridView] 为被测对象，不经过路由；缩略图经
/// [PreActivatedMediaLibrarySessionController] 走 [FakeMediaLibrary] 的可观察解析。
Future<void> _pumpMediaGrid(
  WidgetTester tester, {
  required SharedPreferences prefs,
  required FakeMediaLibrary library,
  required List<FileItem> items,
  Size viewportSize = const Size(1440, 1200),
}) {
  return pumpTestApp(
    tester,
    preferences: prefs,
    viewportSize: viewportSize,
    extraOverrides: [
      mediaLibrarySessionProvider.overrideWith(
        () => PreActivatedMediaLibrarySessionController(library),
      ),
    ],
    child: Scaffold(
      body: Column(
        children: [
          MediaPathBar(currentPath: '/', onPathSelected: (_) {}),
          const Divider(height: 1),
          Expanded(
            child: MediaGridView(
              items: items,
              isLoading: false,
              onItemTap: (_) {},
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  // 固定三列缺陷回归：目录/图片/视频在宽窄视口均渲染且无异常
  const mediaGridSmokeViewports = [
    Size(390, 844),
    Size(960, 640),
    Size(1440, 900),
  ];

  for (final viewportSize in mediaGridSmokeViewports) {
    testWidgets(
      '${viewportSize.width}x${viewportSize.height}: 目录/图片/视频可达且无异常',
      (tester) async {
        final prefs = await _testPrefs();
        await _pumpMediaGrid(
          tester,
          prefs: prefs,
          library: FakeMediaLibrary(),
          viewportSize: viewportSize,
          items: [
            _dir('/相册'),
            _file('/相册/猫.jpg', hasThumbnail: true),
            _file('/视频/demo.mp4'),
          ],
        );

        expect(find.byType(MediaGridView), findsOneWidget);
        expect(find.text('相册'), findsOneWidget);
        expect(find.text('猫.jpg'), findsOneWidget);
        expect(find.text('demo.mp4'), findsOneWidget);
        expect(find.byIcon(Icons.folder), findsOneWidget);
        expect(find.byIcon(Icons.image), findsOneWidget);
        expect(find.byIcon(Icons.movie), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('放大文字时长文件名/目录/带大小文件渲染无异常且 tooltip 可访问', (tester) async {
    final prefs = await _testPrefs();
    const longName = '这是一个用于验证放大文字和省略号的很长文件名.jpg';
    // 系统文字放大：网格重新解析统一行高，不覆盖 TextScaler、不缩小字体
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pumpMediaGrid(
      tester,
      prefs: prefs,
      library: FakeMediaLibrary(),
      items: [
        _file('/相册/$longName', hasThumbnail: true),
        _dir('/相册/长目录名'),
        _file('/相册/带大小文件.bin', sizeBytes: 2048),
      ],
    );

    // 超长文件名被省略号截断，但完整名称经 Tooltip 仍可访问
    expect(find.text(longName), findsOneWidget);
    expect(find.byTooltip(longName), findsOneWidget);
    expect(find.text('长目录名'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('初帧解析缩略图后缩放视口不重复解析同一请求', (tester) async {
    final prefs = await _testPrefs();
    final library = FakeMediaLibrary();
    const request = MediaThumbnailRequest(
      relativePath: '/相册/照片.jpg',
      sizeBytes: 1,
      lastModified: 0,
      hasThumbnail: true,
    );
    await _pumpMediaGrid(
      tester,
      prefs: prefs,
      library: library,
      viewportSize: const Size(960, 640),
      items: [
        _file('/相册/照片.jpg', hasThumbnail: true),
        _file('/相册/文档.txt'),
        _dir('/视频'),
      ],
    );

    // 初帧等待缩略图 Future 完成：解析结果为 null → 回退图标，不触发图片加载
    await tester.pump();
    expect(library.resolveThumbnailCalls, [request]);

    // 缩放视口后网格重排，仍可见项的同一缩略图不得重新解析
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pump();
    expect(library.resolveThumbnailCalls, [request]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('密度切换保持目录、锚点可达且已可见缩略图不重复解析', (tester) async {
    final prefs = await _testPrefs({mediaGridDensityStorageKey: 'compact'});
    final library = FakeMediaLibrary();
    final items = List<FileItem>.generate(40, (index) {
      if (index == 0) return _file('/相册/首位缩略图.jpg', hasThumbnail: true);
      if (index == 5) return _dir('/相册/中部目录');
      if (index == 20) return _file('/相册/中部锚点.txt');
      return _file('/相册/文件$index.txt');
    });
    const topRequest = MediaThumbnailRequest(
      relativePath: '/相册/首位缩略图.jpg',
      sizeBytes: 1,
      lastModified: 0,
      hasThumbnail: true,
    );

    await _pumpMediaGrid(
      tester,
      prefs: prefs,
      library: library,
      viewportSize: const Size(960, 640),
      items: items,
    );
    await tester.pump();

    // 滚动到列表中部：位于中部的命名锚点进入可见区
    await tester.drag(find.byType(MediaGridView), const Offset(0, -250));
    await tester.pump();
    expect(find.text('中部锚点.txt'), findsOneWidget);
    // 滚动后首位缩略图仍在视口/缓存内，仍只解析一次
    expect(library.resolveThumbnailCalls, [topRequest]);

    // 通过 controller 从 compact 切到 comfortable
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MediaGridView)),
    );
    await container
        .read(mediaGridDensityProvider.notifier)
        .select(AppLayoutDensity.comfortable);
    await tester.pump();

    // 当前目录状态不变：路径栏仍停留在根目录
    expect(find.text('🏠'), findsOneWidget);
    // 同一可见缩略图没有新增解析调用
    expect(library.resolveThumbnailCalls, [topRequest]);

    // 原本位于中部的命名锚点仍可达
    await tester.scrollUntilVisible(
      find.text('中部锚点.txt'),
      100,
      scrollable: find.descendant(
        of: find.byType(MediaGridView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pump();
    expect(find.text('中部锚点.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

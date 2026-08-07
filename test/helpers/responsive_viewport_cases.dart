import 'package:flutter/widgets.dart';

/// 应用壳在当前视口下应呈现的导航模式。
enum ShellNavigationMode { bottomBar, rail }

/// 一个共享的响应式测试视口描述：宽度 + 壳层导航期望。
final class ResponsiveViewportCase {
  const ResponsiveViewportCase({
    required this.name,
    required this.size,
    required this.shellMode,
  });

  final String name;
  final Size size;
  final ShellNavigationMode shellMode;
}

/// 手机竖屏：常见移动端与最窄核心场景。
const phonePortrait = ResponsiveViewportCase(
  name: 'phonePortrait',
  size: Size(390, 844),
  shellMode: ShellNavigationMode.bottomBar,
);

/// 紧凑平板：消息气泡代表值与 compact 页面。
const compactTablet = ResponsiveViewportCase(
  name: 'compactTablet',
  size: Size(600, 900),
  shellMode: ShellNavigationMode.bottomBar,
);

/// 壳层断点前一像素：仍为紧凑。
const shellBelowBoundary = ResponsiveViewportCase(
  name: 'shellBelowBoundary',
  size: Size(719, 900),
  shellMode: ShellNavigationMode.bottomBar,
);

/// 壳层断点等号：恰好 720 进入宽侧（rail）。
const shellAtBoundary = ResponsiveViewportCase(
  name: 'shellAtBoundary',
  size: Size(720, 900),
  shellMode: ShellNavigationMode.rail,
);

/// 壳层断点后一像素：稳定在宽侧。
const shellAboveBoundary = ResponsiveViewportCase(
  name: 'shellAboveBoundary',
  size: Size(721, 900),
  shellMode: ShellNavigationMode.rail,
);

/// 平板/窄桌面。
const desktop = ResponsiveViewportCase(
  name: 'desktop',
  size: Size(1024, 768),
  shellMode: ShellNavigationMode.rail,
);

/// 常规桌面；高度 900，避免用 1200/1600 的高度掩盖滚动问题。
const wideDesktop = ResponsiveViewportCase(
  name: 'wideDesktop',
  size: Size(1440, 900),
  shellMode: ShellNavigationMode.rail,
);

/// 全部必需的七个壳层视口。
const requiredShellViewports = [
  phonePortrait,
  compactTablet,
  shellBelowBoundary,
  shellAtBoundary,
  shellAboveBoundary,
  desktop,
  wideDesktop,
];

/// Android 横屏低高度场景，供 Sync/Media 使用；不并入壳层循环。
const androidLandscape = Size(844, 390);

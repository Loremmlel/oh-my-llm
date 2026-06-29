import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 全屏图片浏览器。
///
/// 支持左右滑动切换图片、双击放大/恢复、双指缩放。
/// 进入时根据 [initialIndex] 定位到被点击的图片，
/// 图片列表来自当前目录下所有图片文件。
class ImageViewerPage extends StatefulWidget {
  /// 当前目录所有图片的 HTTP URL 列表。
  final List<String> imageUrls;

  /// 被点击图片在 [imageUrls] 中的索引。
  final int initialIndex;

  ImageViewerPage({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  }) : assert(initialIndex >= 0),
       assert(imageUrls.isNotEmpty),
       assert(initialIndex < imageUrls.length);

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage>
    with TickerProviderStateMixin {
  late final PageController _pageController;
  int _currentIndex = 0;

  /// 每页缩放状态，key 为页面索引。
  ///
  /// 使用 Map 管理以消除页面切换时的 race condition——
  /// 旧页延迟到达的缩放回调不会错误地覆盖新页状态。
  final Map<int, bool> _pageZoomStates = {};

  /// 是否有任一页面处于缩放状态。
  bool get _anyZoomed => _pageZoomStates.values.any((v) => v);

  /// 双击缩放动画控制器。
  ///
  /// 驱动 200ms 的 Matrix4 Tween 动画。开始新动画前先 stop() 旧动画，
  /// 确保快速双击时状态一致。
  late final AnimationController _zoomAnimationController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _zoomAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    // 初始化当前页为非缩放状态
    _pageZoomStates[widget.initialIndex] = false;

    // 沉浸式全屏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _zoomAnimationController.dispose();
    // 恢复系统 UI 模式
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  // ── 缩放状态回调 ──────────────────────────────────────────────

  void _onZoomChanged(int pageIndex, bool isZoomed) {
    if (!mounted) return;
    setState(() {
      _pageZoomStates[pageIndex] = isZoomed;
    });
  }

  // ── 构建 ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── 图片 PageView ──
          PageView.builder(
            controller: _pageController,
            physics:
                _anyZoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
            itemCount: widget.imageUrls.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
              // 确保新页面在 Map 中有初始状态（不存在时默认 false）
              _pageZoomStates.putIfAbsent(index, () => false);
            },
            itemBuilder: (context, index) {
              return _ZoomableImagePage(
                imageUrl: widget.imageUrls[index],
                pageIndex: index,
                isZoomed: _pageZoomStates[index] ?? false,
                zoomAnimationController: _zoomAnimationController,
                onZoomChanged: _onZoomChanged,
              );
            },
          ),
          // ── 顶部覆盖层 ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          // 页面计数器
          if (widget.imageUrls.length > 1)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_currentIndex + 1} / ${widget.imageUrls.length}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 单页缩放图片组件 ────────────────────────────────────────────────

/// Zoomable 单页图片。
///
/// 封装 InteractiveViewer（双指缩放 + 平移）和 GestureDetector（双击缩放）。
/// 使用 hysteresis 判断缩放状态，避免在边界反弹时频繁切换 PageView physics。
class _ZoomableImagePage extends StatefulWidget {
  final String imageUrl;
  final int pageIndex;
  final bool isZoomed;
  final AnimationController zoomAnimationController;
  final void Function(int pageIndex, bool isZoomed) onZoomChanged;

  const _ZoomableImagePage({
    required this.imageUrl,
    required this.pageIndex,
    required this.isZoomed,
    required this.zoomAnimationController,
    required this.onZoomChanged,
  });

  @override
  State<_ZoomableImagePage> createState() => _ZoomableImagePageState();
}

class _ZoomableImagePageState extends State<_ZoomableImagePage> {
  final TransformationController _transformController =
      TransformationController();

  /// 当前是否处于图片加载失败状态。
  bool _hasError = false;

  /// 双击缩放动画监听器引用，用于在添加新监听器前移除旧监听器。
  VoidCallback? _animationListener;

  /// 最近一次双击的落点位置，用于将缩放焦点对准点击处。
  Offset? _lastDoubleTapPosition;

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransformChanged);
    // 页面被 PageView 回收重建时通知父级重置缩放状态。
    // 延迟到下一帧：initState 在 build 期间被调用，不能同步触发父级 setState。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onZoomChanged(widget.pageIndex, false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _ZoomableImagePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换图片时重置错误状态和变换矩阵
    if (oldWidget.imageUrl != widget.imageUrl) {
      _hasError = false;
      _transformController.value = Matrix4.identity();
      // 延迟通知父级：didUpdateWidget 也在父级 build 期间被调用
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onZoomChanged(widget.pageIndex, false);
        }
      });
    }
  }

  @override
  void dispose() {
    // 清理动画监听器，防止泄漏
    if (_animationListener != null) {
      widget.zoomAnimationController.removeListener(_animationListener!);
      _animationListener = null;
    }
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  // ── 缩放变换监听 ──────────────────────────────────────────────

  /// hysteresis 阈值：
  /// - 放大超过 1.10 进入缩放模式
  /// - 缩小低于 1.01 退出缩放模式
  ///
  /// 滞后区间避免 InteractiveViewer 边界反弹时频繁切换 PageView physics。
  static const double _zoomEnterThreshold = 1.10;
  static const double _zoomExitThreshold = 1.01;

  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    final wasZoomed = widget.isZoomed;

    bool newZoomed;
    if (wasZoomed) {
      // 已在缩放模式：需要缩到很接近 1.0 才退出
      newZoomed = scale > _zoomExitThreshold;
    } else {
      // 未缩放模式：需要明显超过 1.0 才进入
      newZoomed = scale > _zoomEnterThreshold;
    }

    if (newZoomed != wasZoomed) {
      widget.onZoomChanged(widget.pageIndex, newZoomed);
    }
  }

  // ── 双击缩放 ──────────────────────────────────────────────────

  void _onDoubleTap() {
    if (_hasError) return; // 加载失败时不响应

    // 中断进行中的动画
    widget.zoomAnimationController.stop();

    // 移除旧监听器，防止泄漏和互相竞争
    if (_animationListener != null) {
      widget.zoomAnimationController.removeListener(_animationListener!);
    }

    final targetIsZoomed = !widget.isZoomed;
    final Matrix4 target;
    if (targetIsZoomed) {
      // 放大：以双击落点为中心缩放
      final pos = _lastDoubleTapPosition ?? Offset.zero;
      target = Matrix4.identity()
        ..translateByDouble(pos.dx, pos.dy, 0.0, 1.0)
        ..scaleByDouble(2.5, 2.5, 1.0, 1.0)
        ..translateByDouble(-pos.dx, -pos.dy, 0.0, 1.0);
    } else {
      // 恢复：直接回到 identity
      target = Matrix4.identity();
    }

    // 捕获固定的起始矩阵（clone 避免后续帧覆盖）
    final Matrix4 start = _transformController.value.clone();

    // 创建新监听器并保存引用
    _animationListener = () {
      if (!mounted) return;
      final t = widget.zoomAnimationController.value;
      _transformController.value = _lerpMatrix(start, target, t);
    };
    widget.zoomAnimationController.addListener(_animationListener!);

    // 执行动画，完成后清理并精确定位到目标值
    widget.zoomAnimationController.reset();
    widget.zoomAnimationController.forward().then((_) {
      // 清理监听器
      if (_animationListener != null) {
        widget.zoomAnimationController.removeListener(_animationListener!);
        _animationListener = null;
      }
      if (!mounted) return;
      _transformController.value = target;
    });
  }

  /// 在两个 Matrix4 之间逐元素线性插值。
  ///
  /// 对于纯缩放矩阵（diagonal3Values）精确等价于几何插值。
  /// InteractiveViewer 当前未启用旋转/透视，元素级 lerp 是安全的。
  static Matrix4 _lerpMatrix(Matrix4 from, Matrix4 to, double t) {
    final result = Matrix4.zero();
    for (int i = 0; i < 16; i++) {
      result[i] = from[i] + (to[i] - from[i]) * t;
    }
    return result;
  }

  // ── 构建 ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 图片加载失败时不包裹 InteractiveViewer，避免空白容器被缩放
    if (_hasError) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image, color: Colors.white54, size: 64),
            SizedBox(height: 12),
            Text(
              '图片加载失败',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return InteractiveViewer(
      transformationController: _transformController,
      minScale: 1.0,
      maxScale: 5.0,
      // 未缩放时禁用手势，消除与 PageView 的手势竞技场竞争
      panEnabled: widget.isZoomed,
      child: GestureDetector(
        onDoubleTapDown: (details) =>
            _lastDoubleTapPosition = details.localPosition,
        onDoubleTap: _onDoubleTap,
        behavior: HitTestBehavior.translucent,
        child: Center(
          child: Image.network(
            widget.imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              final total = loadingProgress.expectedTotalBytes;
              final progress =
                  total != null
                      ? loadingProgress.cumulativeBytesLoaded / total
                      : null;
              return Center(
                child: CircularProgressIndicator(
                  value: progress,
                  color: Colors.white54,
                ),
              );
            },
            errorBuilder: (context, error, stack) {
              // 在下一帧设置错误状态，避免在 build 中 setState
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() => _hasError = true);
                }
              });
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }
}

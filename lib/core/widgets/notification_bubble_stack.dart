import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/notification_bubble_provider.dart';
import 'notification_bubble.dart';
import 'notification_bubble_data.dart';

/// 全局通知气泡堆叠容器。
///
/// 在 [MaterialApp.builder] 中作为 Overlay 层插入，始终悬浮于右上角。
/// 最多同时可见 3 条，新通知将旧通知向下挤。
class NotificationBubbleStack extends ConsumerStatefulWidget {
  const NotificationBubbleStack({super.key});

  @override
  ConsumerState<NotificationBubbleStack> createState() =>
      _NotificationBubbleStackState();
}

class _NotificationBubbleStackState
    extends ConsumerState<NotificationBubbleStack> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();

  /// 当前在 AnimatedList 中渲染的数据，与 Provider 状态保持同步。
  List<NotificationBubbleData> _displayed = [];

  /// 首次构建标记——避免 [AnimatedList.initialItemCount] 与 [AnimatedListState.insertItem]
  /// 同时生效导致幽灵条目。
  bool _needsInit = true;

  @override
  Widget build(BuildContext context) {
    final currentState = ref.watch(notificationBubblesProvider);

    // 首次非空：initialItemCount 已正确处理初始条目，跳过同步。
    // 后续变更：对比新旧列表，在 post-frame 中驱动 AnimatedList 插入/移除动画。
    // post-frame 延迟是为了避免 build 期间修改 AnimatedList 导致框架断言失败。
    if (_needsInit && currentState.isNotEmpty) {
      _needsInit = false;
      _displayed = List<NotificationBubbleData>.of(currentState);
    } else if (_needsInit && currentState.isEmpty) {
      // 仍为空，保持标记等待首条通知。
    } else if (!_listContentEquals(_displayed, currentState)) {
      final previousState = List<NotificationBubbleData>.of(_displayed);
      _displayed = List<NotificationBubbleData>.of(currentState);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _syncLists(previousState, currentState);
        }
      });
    }

    // 全部消失后重置初始化标记，下次出现时从头开始。
    if (currentState.isEmpty) {
      _needsInit = true;
      _displayed = [];
      return const SizedBox.shrink();
    }

    if (_displayed.isEmpty) return const SizedBox.shrink();

    // 在 build 顶部一次获取 MediaQuery，避免后续多次树遍历。
    final mq = MediaQuery.of(context);
    final topPadding = mq.padding.top + 8;

    return Positioned(
      top: topPadding,
      right: 8,
      child: SizedBox(
        width: _bubbleWidth(mq.size.width),
        child: AnimatedList(
          key: _listKey,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // 仅首次创建时生效；后续由 insertItem/removeItem 维护。
          initialItemCount: _displayed.length,
          itemBuilder: _buildInsertItem,
        ),
      ),
    );
  }

  // ── AnimatedList 同步 ──────────────────────────────────────────

  /// 对比新旧列表，调用 insertItem / removeItem 驱动动画。
  ///
  /// 先处理移除（倒序遍历避免索引错位），再处理插入——因为同一
  /// 步骤内 insert+remove 发生在不同索引时，倒序移除保证索引稳定。
  void _syncLists(
    List<NotificationBubbleData> oldList,
    List<NotificationBubbleData> newList,
  ) {
    final listState = _listKey.currentState;
    if (listState == null) return;

    final oldIds = oldList.map((d) => d.id).toList();
    final newIds = newList.map((d) => d.id).toList();
    final oldIdSet = oldIds.toSet();
    final newIdSet = newIds.toSet();

    // 倒序移除：从后往前删除，避免索引错位。
    for (var i = oldIds.length - 1; i >= 0; i -= 1) {
      if (!newIdSet.contains(oldIds[i])) {
        listState.removeItem(
          i,
          (context, animation) => _buildRemoveItem(oldList[i], animation),
          duration: const Duration(milliseconds: 200),
        );
      }
    }

    // 正序插入。
    for (var i = 0; i < newIds.length; i += 1) {
      if (!oldIdSet.contains(newIds[i])) {
        listState.insertItem(
          i,
          duration: const Duration(milliseconds: 300),
        );
      }
    }
  }

  // ── 列表相等性 ──────────────────────────────────────────────────

  bool _listContentEquals(
    List<NotificationBubbleData> a,
    List<NotificationBubbleData> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  // ── 列表项构建 ──────────────────────────────────────────────────

  /// 入场动画：从右侧滑入 + 淡入，300ms ease-out。
  Widget _buildInsertItem(BuildContext context, int index, Animation<double> animation) {
    if (index >= _displayed.length) return const SizedBox.shrink();
    final data = _displayed[index];

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOut),
        ),
        child: NotificationBubbleContent(
          data: data,
          onDismiss: () => _onDismiss(data.id),
        ),
      ),
    );
  }

  /// 出场动画：向右滑出 + 淡出，200ms ease-in。
  /// 关闭按钮在动画期间隐藏，避免用户点击无响应的死区。
  Widget _buildRemoveItem(
    NotificationBubbleData data,
    Animation<double> animation,
  ) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(1.0, 0.0),
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeIn)),
      child: FadeTransition(
        opacity: Tween<double>(begin: 1.0, end: 0.0).animate(animation),
        child: NotificationBubbleContent(
          data: data,
          onDismiss: () {},
          showCloseButton: false,
        ),
      ),
    );
  }

  // ── 关闭回调 ────────────────────────────────────────────────────

  void _onDismiss(String id) {
    ref.read(notificationBubblesProvider.notifier).dismiss(id);
  }

  // ── 宽度计算 ────────────────────────────────────────────────────

  /// 气泡宽度 = 屏幕宽度的 50%，上限 320px。
  ///
  /// 小屏设备（≤360px）改用 90% 宽度以保证可读性。
  double _bubbleWidth(double screenWidth) {
    if (screenWidth <= 360) {
      return screenWidth * 0.9;
    }
    final half = screenWidth * 0.5;
    return half > 320 ? 320 : half;
  }
}

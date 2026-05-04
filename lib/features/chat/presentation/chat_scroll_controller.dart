import 'package:flutter/widgets.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../domain/models/chat_message.dart';

/// 聊天页滚动与锚点管理器。
///
/// 封装消息列表的 [ItemScrollController] 和 [ItemPositionsListener]，
/// 以及「滚到底部」按钮和用户消息锚点的推导逻辑。
/// 通过 [onStateChange] 回调通知宿主 [State] 触发 [setState]，
/// 通过 [isMounted] 回调检查宿主 State 是否仍挂载在树上。
///
/// 宿主在 [State.initState] 里创建本对象并注册监听：
/// ```dart
/// _scroll = ChatScrollController(
///   onStateChange: () => setState(() {}),
///   isMounted: () => mounted,
/// );
/// _scroll.itemPositionsListener.itemPositions.addListener(
///   _scroll.handleVisibleItemsChanged,
/// );
/// ```
/// 并在 [State.dispose] 里反注册：
/// ```dart
/// _scroll.itemPositionsListener.itemPositions.removeListener(
///   _scroll.handleVisibleItemsChanged,
/// );
/// ```
class ChatScrollController {
  ChatScrollController({
    required VoidCallback onStateChange,
    required bool Function() isMounted,
  }) : _onStateChange = onStateChange,
       _isMounted = isMounted;

  final VoidCallback _onStateChange;
  final bool Function() _isMounted;

  final ItemScrollController itemScrollController = ItemScrollController();
  final ItemPositionsListener itemPositionsListener =
      ItemPositionsListener.create();

  /// 当前是否需要显示「滚到底部」按钮。
  bool showScrollToBottom = false;

  /// 当前高亮的用户消息锚点 ID。
  String? activeAnchorMessageId;

  String? _lastConversationId;
  String? _lastRenderSignature;
  List<ChatMessage> _latestMessages = const [];
  List<ChatMessage> _latestUserMessages = const [];
  List<int> _latestUserMessageIndexes = const [];
  Map<String, int> _latestMessageIndexById = const {};

  /// 上一帧中最后一条消息的 leading edge（viewport 分数）。
  /// 负值表示 leading edge 在 viewport 顶部之上（消息比 viewport 更高）。
  double _lastItemLeadingEdge = 0;

  /// 上一帧中最后一条消息的 trailing edge（viewport 分数）。
  double _lastItemTrailingEdge = 0;

  // ── 元数据缓存 ──────────────────────────────────────────────────────────────

  /// 缓存当前可见列表所需的索引信息，避免滚动监听里重复全量计算。
  void cacheVisibleMessageMetadata(
    List<ChatMessage> messages,
    List<ChatMessage> userMessages,
  ) {
    _latestMessages = messages;
    _latestUserMessages = userMessages;
    _latestMessageIndexById = <String, int>{
      for (var index = 0; index < messages.length; index += 1)
        messages[index].id: index,
    };
    _latestUserMessageIndexes = <int>[
      for (var index = 0; index < messages.length; index += 1)
        if (messages[index].role == ChatMessageRole.user) index,
    ];
  }

  // ── 滚动触发 ────────────────────────────────────────────────────────────────

  /// 根据会话内容变化决定是否自动滚动到末尾。
  void scheduleScrollSync({
    required String conversationId,
    required List<ChatMessage> messages,
    required bool isStreaming,
  }) {
    final signature = [
      conversationId,
      messages.length,
      messages.lastOrNull?.content.length ?? 0,
      messages.lastOrNull?.reasoningContent.length ?? 0,
      isStreaming,
    ].join('|');

    if (_lastConversationId != conversationId) {
      _lastConversationId = conversationId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isMounted()) return;
        scrollToBottom(jump: true);
      });
    } else if (_lastRenderSignature != signature) {
      final shouldAutoScroll = !showScrollToBottom;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isMounted()) return;
        if (shouldAutoScroll) scrollToBottom();
      });
    }

    _lastRenderSignature = signature;
  }

  /// 滚动到消息列表底部；[jump] 为 true 时直接跳转，否则平滑动画。
  ///
  /// alignment 由 [_computeScrollAlignment] 动态计算：
  /// - 当最后一条消息较短（完全在 viewport 内）时，使用 0（leading edge 对齐顶部），
  ///   这样整条消息从头可见；
  /// - 当最后一条消息比 viewport 更高时（streaming 长回复），使用负值 alignment，
  ///   使 trailing edge 对齐到 viewport 底部，避免滚回消息开头的回弹问题。
  Future<void> scrollToBottom({bool jump = false}) async {
    if (_latestMessages.isEmpty || !itemScrollController.isAttached) return;

    final targetIndex = _latestMessages.length - 1;
    if (jump) {
      itemScrollController.jumpTo(index: targetIndex, alignment: 0);
      _scheduleVisibleItemsSync();
      return;
    }

    await itemScrollController.scrollTo(
      index: targetIndex,
      alignment: _computeScrollAlignment(),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
    _scheduleVisibleItemsSync();
  }

  /// 根据上一帧的最后一条消息位置计算合适的 alignment。
  ///
  /// - 如果消息 leading edge ≥ 0（消息从 viewport 顶部或以内开始），返回 0；
  ///   此时 alignment: 0 把 leading edge 对齐顶部，短消息完整可见。
  /// - 如果消息 leading edge < 0（消息比 viewport 更高，leading edge 已超出顶部），
  ///   返回 `1.0 - height`（height 为 trailing – leading 的 viewport 分数）；
  ///   此时 trailing edge 恰好对齐到 viewport 底部，用户看到消息末尾。
  double _computeScrollAlignment() {
    if (_lastItemLeadingEdge >= 0) return 0;
    final height = _lastItemTrailingEdge - _lastItemLeadingEdge;
    if (height <= 0) return 0;
    return 1.0 - height;
  }

  /// 滚动到某条指定消息。
  Future<void> scrollToMessage(String messageId) async {
    final targetIndex = _latestMessageIndexById[messageId];
    if (targetIndex == null || !itemScrollController.isAttached) return;

    await itemScrollController.scrollTo(
      index: targetIndex,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: 0.12,
    );
  }

  // ── 可见性监听 ──────────────────────────────────────────────────────────────

  /// 根据当前可见项更新「滚到底部」按钮和激活锚点，并更新最后一条消息的位置缓存。
  void handleVisibleItemsChanged() {
    if (!_isMounted()) return;

    final positions = itemPositionsListener.itemPositions.value
        .where((p) => p.index >= 0 && p.index < _latestMessages.length)
        .toList(growable: false)
      ..sort((l, r) => l.index.compareTo(r.index));

    // 更新最后一条消息的位置缓存，供 _computeScrollAlignment 使用。
    final lastRealIndex = _latestMessages.length - 1;
    final lastItemPos =
        positions.where((p) => p.index == lastRealIndex).firstOrNull;
    if (lastItemPos != null) {
      _lastItemLeadingEdge = lastItemPos.itemLeadingEdge;
      _lastItemTrailingEdge = lastItemPos.itemTrailingEdge;
    }

    final nextShowScrollToBottom = _resolveShowScrollToBottom(positions);
    final nextActiveAnchorMessageId = _resolveActiveAnchorMessageId(positions);

    if (showScrollToBottom == nextShowScrollToBottom &&
        activeAnchorMessageId == nextActiveAnchorMessageId) {
      return;
    }

    showScrollToBottom = nextShowScrollToBottom;
    activeAnchorMessageId = nextActiveAnchorMessageId;
    _onStateChange();
  }

  /// 在主动滚动后补一次可见项同步，避免按钮状态滞后到下一次滚动事件。
  void _scheduleVisibleItemsSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isMounted()) return;
      handleVisibleItemsChanged();
    });
  }

  // ── 状态推导 ────────────────────────────────────────────────────────────────

  /// 根据当前可见项判断是否已经接近列表底部。
  bool _resolveShowScrollToBottom(List<ItemPosition> positions) {
    if (_latestMessages.isEmpty || positions.isEmpty) return false;

    final last = positions
        .where((p) => p.index == _latestMessages.length - 1)
        .firstOrNull;
    if (last == null) return true;

    return last.itemTrailingEdge > 1.01;
  }

  /// 根据当前可见消息位置推导出最合适的用户消息锚点。
  String? _resolveActiveAnchorMessageId(List<ItemPosition> positions) {
    if (_latestUserMessages.isEmpty || positions.isEmpty) return null;

    var bestVisibleAnchorId = '';
    var bestVisibleDistance = double.infinity;

    for (final position in positions) {
      final message = _latestMessages[position.index];
      if (message.role != ChatMessageRole.user) continue;

      final center = (position.itemLeadingEdge + position.itemTrailingEdge) / 2;
      final distance = (center - 0.5).abs();
      if (distance < bestVisibleDistance) {
        bestVisibleDistance = distance;
        bestVisibleAnchorId = message.id;
      }
    }

    if (bestVisibleAnchorId.isNotEmpty) return bestVisibleAnchorId;

    final firstVisibleIndex = positions.first.index;
    final lastVisibleIndex = positions.last.index;
    final nearestAboveIndex = _latestUserMessageIndexes.lastWhere(
      (index) => index <= firstVisibleIndex,
      orElse: () => -1,
    );
    if (nearestAboveIndex >= 0) return _latestMessages[nearestAboveIndex].id;

    final nearestBelowIndex = _latestUserMessageIndexes.firstWhere(
      (index) => index >= lastVisibleIndex,
      orElse: () => -1,
    );
    if (nearestBelowIndex >= 0) return _latestMessages[nearestBelowIndex].id;

    return _latestUserMessages.first.id;
  }
}

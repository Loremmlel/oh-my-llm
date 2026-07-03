import 'package:flutter/material.dart';

import '../../domain/chat_conversation_groups.dart';
import '../../domain/models/chat_conversation_summary.dart';

/// 按时间分组并虚拟化渲染的会话列表。
///
/// 封装了「分组 → 扁平化 → ListView.builder 按运行时类型分发」的完整链路，
/// 使 [HistoryScreen] 和 [ConversationHistoryPanel] 共享同一渲染骨架，
/// 避免在多处重复 `groupConversationSummariesByUpdatedAt` +
/// `flattenConversationSummaryGroups` + `is ConversationTimeBucket` 分发逻辑。
class GroupedConversationList extends StatelessWidget {
  const GroupedConversationList({
    required this.groups,
    required this.itemBuilder,
    super.key,
    this.scrollController,
    this.headerBuilder,
    this.shrinkWrap = false,
    this.physics,
    this.cacheExtent,
  });

  /// 按时间排序后的会话分组。
  final List<ChatConversationSummaryGroup> groups;

  /// 对话条目的 builder。
  final Widget Function(BuildContext context, ChatConversationSummary conversation)
  itemBuilder;

  /// 组标题的 builder（可选；默认渲染为 `Text(bucket.label)`）。
  final Widget Function(BuildContext context, ConversationTimeBucket bucket)?
  headerBuilder;

  final ScrollController? scrollController;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final double? cacheExtent;

  @override
  Widget build(BuildContext context) {
    final flatItems = flattenConversationSummaryGroups(groups);

    return ListView.builder(
      controller: scrollController,
      shrinkWrap: shrinkWrap,
      physics: physics,
      cacheExtent: cacheExtent,
      itemCount: flatItems.length,
      itemBuilder: (context, index) {
        final item = flatItems[index];

        if (item is ConversationTimeBucket) {
          return headerBuilder?.call(context, item) ??
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Text(
                  item.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              );
        }

        return itemBuilder(context, item as ChatConversationSummary);
      },
    );
  }
}

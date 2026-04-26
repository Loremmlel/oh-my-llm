import '../../../core/widgets/feature_placeholder_view.dart';

class HistoryPlaceholderScreen extends FeaturePlaceholderView {
  const HistoryPlaceholderScreen({super.key})
      : super(
          title: '历史对话页',
          description: '历史记录页的时间分组、检索和批量管理能力会在后续能力块中接入。',
          highlights: const [
            '已预留独立路由，便于后续补充列表和搜索体验。',
            '会话模型已具备标题、时间戳和消息集合等基础字段。',
          ],
        );
}

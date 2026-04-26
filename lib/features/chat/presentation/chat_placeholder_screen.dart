import '../../../core/widgets/feature_placeholder_view.dart';

class ChatPlaceholderScreen extends FeaturePlaceholderView {
  const ChatPlaceholderScreen({super.key})
      : super(
          title: '对话页',
          description: '项目基础架构已经就绪，下一步会把完整的对话交互和响应式布局接进来。',
          highlights: const [
            '已建立应用级主题、路由与状态管理入口。',
            '已准备对话、模型配置、前置 Prompt 的核心数据模型骨架。',
            '后续功能可以在稳定目录结构上按能力块继续提交。',
          ],
        );
}

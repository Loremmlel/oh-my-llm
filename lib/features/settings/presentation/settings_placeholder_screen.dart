import '../../../core/widgets/feature_placeholder_view.dart';

class SettingsPlaceholderScreen extends FeaturePlaceholderView {
  const SettingsPlaceholderScreen({super.key})
      : super(
          title: '设置页',
          description: '模型配置和前置 Prompt 管理会在后续能力块中基于这里的领域模型继续实现。',
          highlights: const [
            '已建立模型配置与 Prompt 模板的数据结构。',
            '本地持久化入口已经在应用启动阶段接入。',
          ],
        );
}

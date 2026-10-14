/// 设置页支持的顶级页签定义。
enum SettingsTab {
  providers('providers', '服务商', '服务商'),
  presets('presets', '预设', '预设 Prompt'),
  prompts('prompts', '提示词', '提示词'),
  network('network', '网络', '网络'),
  outputProcessing('output_processing', '输出处理', '输出处理'),
  other('other', '其它', '其它设置'),
  worldBooks('world_books', '世界书', '世界书');

  const SettingsTab(this.key, this.label, this.exportLabel);

  /// 持久化与传输使用的唯一稳定标识符。
  final String key;

  /// 页签栏显示的紧凑短文案。
  final String label;

  /// 导出提示或完整标题使用的文案。
  final String exportLabel;

  /// 默认页签展示顺序。
  static const List<SettingsTab> defaultOrder = [
    providers,
    presets,
    prompts,
    network,
    outputProcessing,
    other,
    worldBooks,
  ];

  /// 根据持久化 key 解析对应的页签，非法 key 返回 null。
  static SettingsTab? fromKey(String key) {
    for (final tab in values) {
      if (tab.key == key) return tab;
    }
    return null;
  }

  /// 清洗外部传入或持久化存储的页签序列：
  /// 1. 过滤未知非法 key；
  /// 2. 保持出现顺序去重；
  /// 3. 若遗漏了默认页签，按默认相对顺序追加在末尾；
  /// 4. 保证结果总是包含全部合法页签且不重复。
  static List<SettingsTab> sanitizeOrder(Iterable<String>? rawKeys) {
    if (rawKeys == null) return List<SettingsTab>.of(defaultOrder);

    final ordered = <SettingsTab>[];
    final seen = <SettingsTab>{};

    for (final rawKey in rawKeys) {
      final tab = fromKey(rawKey);
      if (tab != null && seen.add(tab)) {
        ordered.add(tab);
      }
    }

    for (final defaultTab in defaultOrder) {
      if (seen.add(defaultTab)) {
        ordered.add(defaultTab);
      }
    }

    return ordered;
  }

  /// 转换为用于持久化存储的 key 列表。
  static List<String> toKeys(Iterable<SettingsTab> tabs) {
    return tabs.map((tab) => tab.key).toList();
  }
}

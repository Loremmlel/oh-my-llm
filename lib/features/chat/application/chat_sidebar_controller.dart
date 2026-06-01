import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/shared_preferences_provider.dart';

/// 聊天页侧边面板的功能入口。
///
/// 每个枚举值代表二级面板（ChatActivityBar）的一个可切换入口，
/// 未来新增功能只需在此枚举中添加成员即可。
enum ChatSidebarFunction {
  history(icon: Icons.history_rounded, label: '历史会话'),
  // 未来扩展：
  // collections(icon: Icons.folder_rounded, label: '收藏夹'),
  ;

  const ChatSidebarFunction({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;
}

/// SharedPreferences 中存储侧边面板状态的键名。
const _prefsKeyActiveFunction = 'sidebar_activeFunction';
const _prefsKeyIsExpanded = 'sidebar_isExpanded';
const _prefsKeyPanelWidth = 'sidebar_panelWidth';

/// 聊天页侧边面板（ActivityBar + SidebarPanel）的 UI 状态。
///
/// 包含当前激活的功能入口、面板展开状态和面板宽度。
/// 状态通过 SharedPreferences 持久化，关闭应用后重新打开时恢复。
class ChatSidebarState extends Equatable {
  const ChatSidebarState({
    this.activeFunction,
    this.isExpanded = true,
    this.panelWidth = 260.0,
  });

  /// 当前激活的功能入口，null 表示无激活项。
  final ChatSidebarFunction? activeFunction;

  /// 三级面板是否展开。
  final bool isExpanded;

  /// 三��面板当前宽度，范围 180px–400px。
  final double panelWidth;

  ChatSidebarState copyWith({
    ChatSidebarFunction? activeFunction,
    bool? isExpanded,
    double? panelWidth,
  }) {
    return ChatSidebarState(
      activeFunction: activeFunction ?? this.activeFunction,
      isExpanded: isExpanded ?? this.isExpanded,
      panelWidth: panelWidth ?? this.panelWidth,
    );
  }

  @override
  List<Object?> get props => [activeFunction, isExpanded, panelWidth];
}

/// 侧边面板状态管理 provider。
final chatSidebarProvider =
    NotifierProvider<ChatSidebarController, ChatSidebarState>(
      ChatSidebarController.new,
    );

/// 侧边面板状态控制器，负责切换功能入口、展开/折叠和面板宽度调整，
/// 并将状态持久化到 SharedPreferences。
class ChatSidebarController extends Notifier<ChatSidebarState> {
  static const double _minPanelWidth = 180.0;
  static const double _maxPanelWidth = 400.0;

  @override
  /// 从 SharedPreferences 恢复上次保存的侧边面板状态。
  ChatSidebarState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final rawFunction = prefs.getString(_prefsKeyActiveFunction);
    // 优先按名称匹配；兼容旧版本按索引持久化的数据。
    ChatSidebarFunction? activeFunction =
        ChatSidebarFunction.values.cast<ChatSidebarFunction?>().firstWhere(
          (f) => f?.name == rawFunction,
          orElse: () => null,
        );
    if (activeFunction == null) {
      final legacyIndex = int.tryParse(rawFunction ?? '');
      if (legacyIndex != null &&
          legacyIndex >= 0 &&
          legacyIndex < ChatSidebarFunction.values.length) {
        activeFunction = ChatSidebarFunction.values[legacyIndex];
      }
    }
    activeFunction ??= ChatSidebarFunction.history;

    final isExpanded = prefs.getBool(_prefsKeyIsExpanded) ?? true;
    final panelWidth =
        (prefs.getDouble(_prefsKeyPanelWidth) ?? 260.0)
            .clamp(_minPanelWidth, _maxPanelWidth);

    return ChatSidebarState(
      activeFunction: activeFunction,
      isExpanded: isExpanded,
      panelWidth: panelWidth,
    );
  }

  /// 切换功能入口：点击已激活的图标切换展开/折叠，点击新图标切换功能并展开。
  void toggleFunction(ChatSidebarFunction function) {
    if (state.activeFunction == function) {
      state = state.copyWith(isExpanded: !state.isExpanded);
    } else {
      state = state.copyWith(activeFunction: function, isExpanded: true);
    }
    _save();
  }

  /// 折叠三级面板，但不改变激活的功能入口。
  void collapse() {
    if (!state.isExpanded) return;
    state = state.copyWith(isExpanded: false);
    _save();
  }

  /// 更新面板宽度并限制在合法范围内。
  void setPanelWidth(double width) {
    final clamped = width.clamp(_minPanelWidth, _maxPanelWidth);
    if ((clamped - state.panelWidth).abs() < 0.5) return;
    state = state.copyWith(panelWidth: clamped);
    _save();
  }

  /// 将当前状态写回 SharedPreferences。
  ///
  /// 使用枚举名称（而非索引）序列化 [ChatSidebarFunction]，确保枚举重排后
  /// 已持久化的值仍然正确。写入失败时打印日志但不阻塞 UI。
  Future<void> _save() async {
    final prefs = ref.read(sharedPreferencesProvider);
    try {
      await Future.wait([
        prefs.setString(
          _prefsKeyActiveFunction,
          state.activeFunction?.name ?? '',
        ),
        prefs.setBool(_prefsKeyIsExpanded, state.isExpanded),
        prefs.setDouble(_prefsKeyPanelWidth, state.panelWidth),
      ]);
    } catch (e) {
      debugPrint('[ChatSidebar] 保存状态失败: $e');
    }
  }
}

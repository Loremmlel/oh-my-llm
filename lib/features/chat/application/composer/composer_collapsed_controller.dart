import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';

/// SharedPreferences 中存储输入区折叠状态的键名。
const _prefsKeyIsComposerCollapsed = 'composer_isCollapsed';

/// 输入区折叠状态的持久化 provider。
///
/// 与 [ChatSidebarController] 同样的模式：状态写入 SharedPreferences，
/// 关闭应用后重新打开时恢复，避免输入区折叠状态在重启后丢失。
final composerCollapsedProvider =
    NotifierProvider<ComposerCollapsedController, bool>(
      ComposerCollapsedController.new,
    );

/// 输入区折叠状态控制器，负责切换折叠/展开并持久化。
class ComposerCollapsedController extends Notifier<bool> {
  @override
  /// 从 SharedPreferences 恢复上次的折叠状态，默认展开（false）。
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool(_prefsKeyIsComposerCollapsed) ?? false;
  }

  /// 切换折叠/展开并持久化。
  ///
  /// 编辑保护（编辑中禁止折叠）由调用方 [ChatScreen] 依据本地
  /// `_editingMessageId` 状态判断，保持 controller 不耦合编辑态。
  void toggle() {
    state = !state;
    _save();
  }

  /// 直接设置折叠状态并持久化，用于退出编辑后恢复到快照值。
  /// 相比 `toggle()`，直接表达「恢复到确定值」而非「翻转」，
  /// 且不依赖调用方先读取当前值做比对。
  void setCollapsed(bool value) {
    if (state == value) return;
    state = value;
    _save();
  }

  /// 将当前状态写回 SharedPreferences，写入失败仅打日志不阻塞 UI。
  Future<void> _save() async {
    final prefs = ref.read(sharedPreferencesProvider);
    try {
      await prefs.setBool(_prefsKeyIsComposerCollapsed, state);
    } catch (e) {
      debugPrint('[ComposerCollapsed] 保存状态失败: $e');
    }
  }
}

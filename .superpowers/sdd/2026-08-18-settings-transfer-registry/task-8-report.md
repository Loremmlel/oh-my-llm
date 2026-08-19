# Task 8 实施报告：设置同步动态分组界面

## 结果

Task 8 已按 brief 完成实现，提交信息为：
`feat(sync): 按注册表动态生成设置同步项`。

Sync 客户端状态现在从 Settings facade 读取有序 group descriptor，操作页和导入确认页均通过 Sync-owned port DTO 与通用摘要组件渲染；旧四分类 adapter 已从 Sync production/test call-site 删除。

## 实现内容

- `SyncClientState` 保存不可变的 `availableGroups`、`selectedGroups` 和 `preparedImport` 投影；controller build 从 facade 复制 descriptor 顺序。
- `toggleGroup` 只接受当前 catalog 中的稳定 ID；未知 ID 忽略；全选复制所有 descriptor ID。
- 每次有效选择变更清除 request-time 敏感确认、prepared import 和 transient error；Equatable 对 group ID 按值排序，不依赖集合迭代顺序。
- 请求开始前捕获精确的不可变 group set，并将同一集合传给协议请求和 incoming preparation；取消会话时保留 catalog 快照。
- `SyncOperationTab` 使用单一 descriptor loop 渲染六个 production group 与测试 descriptor；label、敏感后缀、全选和请求前 warning 均由 descriptor 驱动。
- `SyncImportConfirmDialog` 将 port `SettingsSyncSummaryItem` 映射为 `TransferSummaryViewItem`，交给 `TransferSummaryList`；保留 PopScope、busy、stale、敏感确认和失败结果行为。
- 删除 `SyncCategory`、旧 sensitivity extension、selectedCategories 状态和 category-to-group mapping。

## 改动文件

代码/测试改动严格限于 brief 白名单中的以下 9 个文件：

- `lib/features/sync/application/sync_client_controller.dart`
- `lib/features/sync/domain/models/protocol/sync_types.dart`
- `lib/features/sync/presentation/widgets/sync_operation_tab.dart`
- `lib/features/sync/presentation/widgets/sync_import_confirm_dialog.dart`
- `test/features/sync/application/sync_test_fakes.dart`
- `test/features/sync/application/sync_client_controller_test.dart`
- `test/app/composition/sync_workspace_screen/sync_workspace_screen_test_helpers.dart`
- `test/app/composition/sync_workspace_screen/sync_workspace_screen_render_cases.dart`
- `test/app/composition/sync_workspace_screen/sync_workspace_screen_import_dialog_cases.dart`

`task-8-report.md` 是 brief 要求的交付记录。既有 `.superpowers/sdd/2026-08-18-settings-transfer-registry/progress.md` 未修改、未暂存。

## TDD RED/GREEN 证据

### RED

命令：

```powershell
flutter test test/features/sync/application/sync_client_controller_test.dart test/features/sync/application/sync_client_controller_execute_test.dart test/app/composition/sync_workspace_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-sync-dynamic-groups-red.log
```

结果：`EXIT=1`。失败集中在实现前不存在的 `availableGroups`、`selectedGroups`、`toggleGroup` 和 `selectAllGroups` API，证明动态 descriptor 测试先于 production 实现捕获旧四分类状态；日志：`logs/settings-sync-dynamic-groups-red.log`。

### GREEN

命令：

```powershell
flutter test test/features/sync/application/sync_client_controller_test.dart test/features/sync/application/sync_client_controller_execute_test.dart test/app/composition/sync_workspace_screen_test.dart test/features/settings/application/transfer/settings_sync_facade_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-sync-dynamic-groups-green.log
```

结果：`EXIT=0`，`62` 个测试通过，日志末尾为 `All tests passed!`；日志：`logs/settings-sync-dynamic-groups-green.log`。

## 其他验证

- `rg -n "SyncCategory|selectedCategories|toggleCategory|selectAllCategories" lib/features/sync test/features/sync test/app/composition`：`ZERO_HITS`。
- `flutter analyze --no-pub`：`EXIT=0`，`No issues found!`；日志：`logs/settings-sync-dynamic-groups-analyze.log`。
- `dart run tool/check_import_boundaries.dart`：`EXIT=0`，检查 `372` 个文件、`0` 条违规；日志：`logs/settings-sync-dynamic-groups-boundary.log`。
- 所有本任务改动 Dart 文件已执行 `dart format`；提交前和暂存后再次执行 `dart format --output=none --set-exit-if-changed`。
- 工作 diff、暂存 diff 的 `git diff --check` 均通过。

## 未做的边界

- 未删除 Task 9 的 legacy workflow/executor。
- 未执行 integration 全量清理，也未修改 integration 测试范围外文件。
- 未修改 `progress.md`，未执行 push、PR、发布、Windows/Android 构建或设备手测。

## Deferred concern

仓库 post-commit hook 会按约定自动 amend `pubspec.yaml` 版本号；该文件是唯一允许的自动附带改动。除该 hook 行为外，没有扩大 Task 8 的源代码/测试范围。导入结果的 stale、partial failure、success/failure 语义仍由既有 port result 类型承载，Task 8 未引入新的跨存储语义。

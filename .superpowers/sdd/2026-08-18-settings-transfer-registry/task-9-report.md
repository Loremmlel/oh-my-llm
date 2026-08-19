# Task 9 实施报告：移除旧设置传输链路并完成端到端组合验证

## 结果

Task 9 已完成实现与验证，提交信息为：
`refactor(settings): 移除旧设置传输链路`。

旧 field aggregate、旧传输 workflow/deduplicator/executor 及其测试已删除；Sync integration 测试现在使用 Sync v4 的稳定 group ID、结构化 Settings transfer v9 document 和 facade descriptors/export/prepare/execute。真实 Provider composition loopback 覆盖了 SQLite 与 SharedPreferences 两类 participant 的跨存储导出导入。

## 删除清单

生产文件：

- `lib/features/settings/domain/models/transfer/settings_export_data.dart`
- `lib/features/settings/domain/models/transfer/settings_export_codec.dart`
- `lib/features/settings/application/transfer/settings_transfer_workflow.dart`
- `lib/features/settings/application/transfer/settings_import_deduplicator.dart`
- `lib/features/settings/application/transfer/settings_import_executor.dart`

测试文件：

- `test/features/settings/domain/models/transfer/settings_export_data_test.dart`
- `test/features/settings/domain/models/transfer/settings_export_codec_test.dart`
- `test/features/settings/application/transfer/settings_transfer_workflow_test.dart`
- `test/features/settings/application/transfer/settings_import_deduplicator_test.dart`
- `test/features/settings/application/transfer/settings_import_executor_test.dart`

## Integration contracts

- `sync_e2e_integration_test.dart` 的真实 composition case 用独立的 `AppDatabase.inMemory()` 与 mock `SharedPreferences` 实例组装服务端/客户端 ProviderContainer。服务端通过真实 catalog 导出 `memoryPrompts`（SQLite merge）和 `customHeaders`（SharedPreferences replace），客户端通过真实 `settingsSyncFacadeProvider` prepare/execute 并验证两个 store 的最终状态。
- loopback HTTP 使用 Sync v4 pairing 和 `SettingsSyncGroupId('prompts'/'network')`；响应断言顶层 `formatVersion == 9`、section key 以及 section value 为结构化 List/Map，而不是嵌套 JSON 字符串。
- 敏感分组先以 `confirmedSensitive: false` 验证服务端在 export 前拒绝；确认后获得 document；客户端 prepare 后再次以 `false` 验证零写入，再以 `true` 完成导入。
- `settings_sync_facade_test.dart` 的现有真实 facade contract 继续证明响应包含未请求 section 时在任何 write 前拒绝；focused final suite 重新执行该测试。
- `sync_multi_category_integration_test.dart` 新增 v9 facade retry case：第一 participant 已成功、第二 participant 注入失败后，重新 prepare 只留下第二项，成功重试不会重复第一项写入。
- production catalog registration 复核为唯一九项；现有 catalog contract/facade 测试继续覆盖 local-only 的 `ChatDefaults`、Settings Tab、media root、media density 不进入 registration/document/descriptor。

## TDD RED/GREEN 证据

### Cleanup red

删除前运行旧 symbol 搜索并写入 `logs/settings-transfer-legacy-red.log`，观察到 `127` 个命中，证明 legacy path 仍存在；删除前更新后的两个 integration 测试和 facade 测试通过，日志为 `logs/settings-transfer-integration-before-cleanup.log`，实际 `EXIT=0`，共 `11` 个测试。

### GREEN

- focused final suite：`flutter test ...`，日志 `logs/settings-transfer-focused-final.log`，实际 `EXIT=0`，`212` 个测试通过。
- full suite：`flutter test --reporter compact`，日志 `logs/fltest.log`，实际 `EXIT=0`，`1929` 个测试通过，末尾为 `All tests passed!`。

## Zero-hit and static verification

- legacy symbols/files：`0` hits；`SyncCategory` / `SettingsSyncSelection`：`0` hits。
- Clipboard boundary：`0` hits；Sync 对 concrete Settings controller：`0` hits。
- `SettingsTransferParticipantBox` / `ErasedSettingsTransferParticipant`：`34` 个 production hits，全部位于 `lib/features/settings/application/transfer/`；unexpected hits `0`。
- production catalog registration：`9`。
- `flutter analyze`：日志 `logs/settings-transfer-analyze.log`，实际 `ANALYZE_EXIT=0`，`No issues found!`。
- `dart run tool/check_import_boundaries.dart`：日志 `logs/settings-transfer-import-boundaries.log`，实际 `BOUNDARY_EXIT=0`，检查 `367` 个文件、`0` 条违规。
- 所有剩余 changed Dart 文件均已执行 `dart format`；暂存后再次执行 `dart format --output=none --set-exit-if-changed` 实际 `EXIT=0`，staged `git diff --check` 实际 `EXIT=0`。

## Scope and concerns

- `.superpowers/sdd/2026-08-18-settings-transfer-registry/progress.md` 是其他 Agent 的未提交 ledger 改动，本任务未修改、未暂存。
- 为满足 brief 明确要求的 Clipboard boundary zero-hit，清除了 `settings_transfer_coordinator.dart` 中一个不影响行为的旧英文注释词；这是严格文件清单之外的唯一 source path，已在交付中显式列出。
- 未修改 schema、未生成代码、未执行 release/build/device 验证，未 push、未创建 PR。
- 本次 full suite 未重现 brief 提到的 `test/features/sync/application/sync_server_controller_test.dart:124` 历史失败。

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

## Fix round 1/5：组合证据补强

本轮只修改 `test/integration/sync_e2e_integration_test.dart` 和本报告；没有修改生产代码、已删除文件或 `progress.md`。

### Red / green

- 先把原跨 store 用例的空 client 断言临时提升为本地 sentinel 断言；在尚未种入 sentinel 的旧 fixture 上实际失败，`logs/settings-transfer-fix-round1-red.log` 记录 `EXIT=1`，失败位置为 client memory 仍为空。这确认了 review 指出的证据缺口，而不是伪造生产失败。
- 补入真实独立 store/provider wiring 后，两个 integration 文件通过，`logs/settings-transfer-fix-round1-focused.log` 实际 `EXIT=0`，共 `7` 个测试。
- brief 指定 focused final suite 实际 `EXIT=0`，`213` 个测试通过，日志为 `logs/settings-transfer-focused-final.log`。
- 串行静态门禁实际 `ANALYZE_EXIT=0`（`No issues found!`，`logs/settings-transfer-analyze.log`）和 `BOUNDARY_EXIT=0`（367 个文件、0 条违规，`logs/settings-transfer-import-boundaries.log`）。
- 全量测试使用 `logs/fltest.log` 和命令层 `240000ms` 超时，实际 `EXIT=0`，`1930` 个测试通过，末尾为 `All tests passed!`。

### Important 证据

- 真实跨 store case 的 client 先用独立 `AppDatabase.inMemory()` 写入 `local-memory`，再用独立 `SharedPreferences` 通过真实 `customHeadersProvider.notifier.save` 写入 `X-Old: old-value`。敏感确认 `false` 后，Riverpod memory provider、SQLite repository、headers provider 和 SharedPreferences raw value 均仍是 sentinel。
- 敏感确认 `true` 后，真实导入结果同时验证 Riverpod/SQLite memory IDs 为 `local-memory` 与 `remote-memory`，证明 merge 保留本地项并加入远端项；headers provider 精确等于仅含 `X-Remote: remote-secret` 的配置，SharedPreferences 持久化值含 `X-Remote` 且不含旧 `X-Old`，证明 replace 清除了旧 header。
- 新增的恶意 response case 只请求 `SettingsSyncGroupId('prompts')`，通过真实 `SyncServerProtocolCoordinator`、loopback `SyncHttpServer`、`HttpSyncClientTransport` 和 `SyncClientProtocolCoordinator` 返回结构化 v9 document；server 记录的 export groups 只有 `prompts`，response 同时注入 `memoryPrompts` 和未请求的 `modelProviders` structured section。
- client 通过真实 Provider composition 取得 `settingsSyncFacadeProvider` 并调用 `prepareIncoming`，在任何 `execute`/participant decode/write 前以精确 safe message `同步内容包含未请求的配置项` 拒绝。拒绝后验证真实 `llmProviderConfigsProvider` 及其 SharedPreferences raw sentinel、SQLite memory provider/repository sentinel、custom headers provider 及其 SharedPreferences raw sentinel 全部不变。
- 两个新 case 均保持 v9 section 为 List/Map，不使用 nested JSON string；本轮没有复活旧 aggregate、v8 fallback 或兼容 wrapper。

### 本轮交付状态

- 本轮未执行 push、未创建 PR；仍只交付本地 commit 和报告。

# Task 3 报告：注册表驱动的导出、准备、重校验与执行

## 完整实现

- 新增 `SettingsTransferCoordinator`，保留 brief 要求的 const constructor，并只暴露四个 public operation：
  - `exportGroups(Set<SettingsTransferGroup>)`
  - `exportValue<T>(SettingsTransferParticipant<T>, T)`
  - `prepareJson(String?, {Set<SettingsTransferGroup>? allowedGroups})`
  - `prepareDocument(SettingsTransferDocument, {Set<SettingsTransferGroup>? allowedGroups})`
- 新增 sealed export preparation/exposure results：无内容、导出批次、敏感确认要求和已暴露 JSON。导出批次保存不可变 document、`summaryItems` 和 `containsSensitive`；敏感内容在未确认时不会序列化为外传文本。
- 新增 sealed import preparation results：malformed、unsupported version、unknown section、section outside allowed groups、invalid participant payload、no changes 和 ready batch。错误只保留安全 code/label/section key，不携带 payload 或异常文本。
- 新增 `SettingsImportBatch`：保存不可变 prepared changes、重校验所需的 allowed groups 和 coordinator 引用，不保存闭包。敏感确认失败不消费 batch；接受执行后一次性消费。
- 执行阶段使用 coordinator 实例级 Future tail 串行化批次；获取锁后重新调用每个 participant 的 `prepareImport`，只比较 fingerprint 与 summary action/count 等摘要字段，支持相同最终 change 的无关本地替换；变化时返回 stale preview 且零写入。
- 写入按 catalog 顺序执行，安全转换所有异常为固定文案 `写入未完成，请检查本地存储后重试`，并准确返回首项失败、部分成功和未执行摘要；成功重复执行返回 already-consumed。
- 为 Task 2 的 erased participant 增加最小内部 `SettingsTransferExportedValue` 边界，使一次 `readLocal()` 同时得到 encoded value 与安全 summary；保留原 `encodeLocalIfExportable()` 行为。
- 新增 fake-participant coordinator 测试，覆盖 brief 列出的导出、跨 group 全局导入、空 merge/空 replace、敏感确认、allowedGroups 门禁、零写入 prepare、stale/同 fingerprint 继续、Future tail 串行、失败/部分失败、一次性执行及新增 participant 无分支接入。

未实现具体九个 participant、Clipboard、Sync 或生产 catalog；未修改 Task 1 document/codec 或其他 feature。

## TDD RED/GREEN 实际证据

### RED

命令（输出写入 `logs/settings-transfer-coordinator-red.log`，60 秒进程 watchdog）：

```powershell
$TestFile = 'test/features/settings/application/transfer/settings_transfer_coordinator_test.dart'
$Command = "flutter test $TestFile --reporter compact > logs/settings-transfer-coordinator-red.log 2>&1"
$Process = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d', '/s', '/c', $Command) -PassThru -WindowStyle Hidden
$Process.WaitForExit(60000)
Write-Host "EXIT=$($Process.ExitCode)"
```

修正测试 fake 的一个遗漏 `isEquivalent` 后，实际结果为 `EXIT=1`。日志明确显示 `settings_transfer_coordinator.dart` 不存在、`SettingsTransferCoordinator` 和全部目标 preparation/execution result 类型缺失；未出现环境启动错误，属于有效产品缺失 RED。

### GREEN

先运行 coordinator 单文件：

```powershell
flutter test test/features/settings/application/transfer/settings_transfer_coordinator_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-coordinator-green.log
```

实际结果：`EXIT=0`，`+16: All tests passed!`。

最终回归命令：

```powershell
flutter test test/features/settings/domain/models/transfer/settings_transfer_document_codec_test.dart test/features/settings/application/transfer/settings_transfer_catalog_test.dart test/features/settings/application/transfer/settings_transfer_coordinator_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-coordinator-green.log
```

实际结果：`FOCUSED_EXIT=0`，日志末尾为 `+46: All tests passed!`。

## 其他验证

- `flutter analyze`：`ANALYZE_EXIT=0`，`No issues found!`；日志：`logs/settings-transfer-analyze.log`。
- `dart run tool/check_import_boundaries.dart`：`BOUNDARY_EXIT=0`，检查 `366` 个文件、`0` 条违规；日志：`logs/settings-transfer-boundary.log`。
- 提交前 `dart format` 覆盖 brief 列出的 6 个 Task 3 Dart 路径：`Formatted 6 files (0 changed)`。
- `dart format --output=none --set-exit-if-changed`：`FORMAT_EXIT=0`。
- `git diff --cached --check`：`DIFF_CHECK_EXIT=0`。
- 实际暂存区在提交前只有 3 个有变更的 task-owned 文件：coordinator、participant 和 coordinator test；brief 中未修改的 Task 2 types/catalog test 没有产生 staged diff。
- 全量测试命令使用 `logs/fltest.log` 和 240 秒 watchdog，实际完成 `EXIT=1`，进度为 `+1939 -1`。唯一失败是既有 `test/features/sync/application/sync_server_controller_test.dart:124`：container dispose 后预期 HTTP 请求抛 `ClientException`，实际仍返回 `Response`；没有 Task 3 文件或测试失败。该失败与 Task 2 报告中的既有 concern 相同，未扩大范围修复。

## 自审

- coordinator 没有按九个具体设置项分支；所有路由、摘要、敏感性、prepare 和 apply 均来自 catalog box。
- `allowedGroups == null` 保持全局 Clipboard 语义；非 null 时在 participant decode 前拒绝已知但未请求的 section。
- prepare 与 stale revalidation 不调用 writer；accepted execution 才进入 Future tail。
- 敏感导出只在 `exposeJson(confirmedSensitive: true)` 返回文本；敏感导入在 batch application boundary 再次确认。
- 失败结果不使用 `error.toString()`；payload、完整 document、API key/Header value 不进入摘要或错误文案。
- 测试标题和新增注释使用简体中文；没有新增 `part` / `part of`，没有修改 Task 1 或其他 feature。

## Concerns

1. 全量测试仍有一个非本任务的既有 Sync 失败，详见 `logs/fltest.log`；Task 3 focused、analyze 和 boundary 均通过。
2. 仓库 post-commit hook 按 `feat(settings):` 自动把版本从 `3.62.2+0` bump 到 `3.63.0+0`，因此最终 commit 自动包含 `pubspec.yaml`，这是 hook 产生的附带变更，不是本任务手动扩大范围。

## Commit

`50dc280d5044859acb09d2ed89c61a017351a775 feat(settings): 统一设置传输编排与执行`

提交后 `git status --short` 为空。

# Task 2 报告：typed participant primitives 与 validated catalog

## 实现

- 新增 `SettingsTransferKey`、六个稳定 `SettingsTransferGroup`、敏感性/摘要动作枚举和带安全文案映射的 `SettingsTransferSummaryItem`。
- 新增 `SettingsTransferParticipant<T>`、`SettingsTransferChange<T>`、`ReplacingValueParticipant<T>` 和 `MergingCollectionParticipant<T>`。
  - 替换策略按完整值比较；相等时 no-op，非空值产生 replace，空值产生 clear。
  - 合并策略按元素内容等价性去重；空集合不导出，`writeValue` 只包含新增项并生成 add count 摘要。
  - 指纹默认来自编码后的完整写入值，具体 participant 继续拥有编解码、等价判断和持久化行为。
- 新增 application-internal 的 `ErasedSettingsTransferParticipant` 与 `SettingsTransferParticipantBox<T>`；类型擦除、恢复、change participant identity 和 value type 校验集中在 box 内。
- 新增 `SettingsTransferCatalog` 与 `SettingsTransferGroupDescriptor`：运行时校验 stable lower-camel key、非空 label、全局唯一 key、组内唯一 order；按 group/order/key 排序；聚合分组敏感性；提供 typed lookup、group lookup 和按组检索。
- 未导入或依赖 Task 1 的 v9 document/codec，也未引入生产 schema snapshot 校验。

## 文件

brief 指定的四个文件已提交：

- `lib/features/settings/application/transfer/settings_transfer_types.dart`
- `lib/features/settings/application/transfer/settings_transfer_participant.dart`
- `lib/features/settings/application/transfer/settings_transfer_catalog.dart`
- `test/features/settings/application/transfer/settings_transfer_catalog_test.dart`

post-commit hook 按仓库既定规则自动修改并纳入 `pubspec.yaml` 版本 bump；该文件不是本任务手动暂存的文件。

## TDD RED/GREEN 证据

初始 RED 命令：

```powershell
flutter test test/features/settings/application/transfer/settings_transfer_catalog_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-catalog-red.log
```

实际结果：`EXIT=1`。失败为预期的 transfer types、participant 和 catalog 类型/构造器缺失；日志未出现 native-assets 或无关启动错误。

补充 collection 写入语义 RED 命令：

```powershell
flutter test test/features/settings/application/transfer/settings_transfer_catalog_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-collection-additions-red.log
```

实际结果：`EXIT=1`；新增项回归用例明确报出预期 `[2]`、实际 `[1, 2]`，随后将基类最小修正为只写入新增项。

最终 GREEN 命令：

```powershell
flutter test test/features/settings/application/transfer/settings_transfer_catalog_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-catalog-green.log
```

实际结果：`EXIT=0`，`13` 个 focused tests 全部通过，日志末尾为 `All tests passed!`。

## 验证结果

- `dart format`：四个任务 Dart 文件格式化完成；提交前 `dart format --output=none --set-exit-if-changed` 返回 `FORMAT_EXIT=0`。
- `git diff --cached --check` 返回 `DIFF_CHECK_EXIT=0`。
- 提交前 staged 文件清单与 brief 的四个路径一致。
- `flutter analyze`：`EXIT=0`，`No issues found!`。
- `dart run tool/check_import_boundaries.dart`：`EXIT=0`，检查 `365` 个文件，`0` 条违规。
- 提交前 focused catalog suite：`EXIT=0`，13/13 通过。

全量测试按 AGENTS.md 使用 `logs/fltest.log` 和 240 秒进程硬超时执行，结果为 `EXIT=1`。唯一失败是未触及的既有测试 `test/features/sync/application/sync_server_controller_test.dart:124`，container dispose 后 HTTP 端口用例预期 `ClientException` 但实际仍返回 `Response`。该文件单独重跑仍以同一断言失败，因此未将无关 Sync 行为带入本任务。

## 自审

- stable key 校验唯一采用 `[a-z][A-Za-z0-9]*`；catalog 不读取 document、formatVersion 或生产 schema fixture，fake key 测试可独立注册。
- catalog 对外只返回非泛型 participant 视图；typed lookup 的错误类型会在读取 participant 时抛出描述性 `StateError`，不会触发 reader/writer。
- raw payload/change casts 均集中在 `settings_transfer_participant.dart` 的 box 实现内；presentation、Sync 和 v9 domain 文件没有新增依赖。
- 测试标题和注释使用简体中文；没有使用 `part` / `part of`，也没有修改 Task 1 document/codec。

## Concerns

1. 仓库全量测试当前仍受既有 `sync_server_controller_test.dart:124` 失败影响；Task 2 focused tests、analyze 和 import-boundary 门禁均通过。
2. post-commit hook 自动执行了版本 bump：`3.61.1+0 -> 3.62.0+0`，所以最终 commit 除四个任务文件外还包含 hook 生成的 `pubspec.yaml` 版本变更。

## Commit

`6a54b8d6c2718ccbacf1ed9127d38352ea1ecb59 feat(settings): 建立设置传输 participant 注册表`

## Fix round 1：收紧 participant 类型擦除边界

### 根因与实现

- 将 `ErasedSettingsTransferParticipant` 改为 sealed contract，唯一实现是同文件的 `SettingsTransferParticipantBox<T>`；移除了 `erase(Object)` 原样返回 erased 实现的路径。
- `SettingsTransferParticipantBox.erase<T>()` 现在只接受带明确 `T` 的公共 `SettingsTransferParticipant<T>`；catalog 通过 `requireBox` 只接受真实 box，未 box 的公共 participant 会在构造时抛出 `ArgumentError`。
- 移除额外的 `SettingsTransferParticipantRuntime` 依赖。box 使用自身的 `T` 无条件校验 local、decoded、incoming、writeValue，并在每次 prepare/reprepare/apply 校验 `identical(change.participant, participant)` 与 `change.valueType == T`。
- prepare 会校验 participant 返回 change 的 identity、change 类型和值；reprepare/apply 会在调用 participant 前拒绝错误 identity、错误 change valueType 和错误写入值。错误输入不会触发 writer。
- 为 merging participant 增加具体 fingerprint 断言，确认指纹来自新增写入集合 `[2]`。

### TDD RED

命令（进程级 60000ms watchdog，输出写入 `logs/settings-transfer-box-red.log`）：

```powershell
$command = "flutter test test/features/settings/application/transfer/settings_transfer_catalog_test.dart --reporter compact > logs/settings-transfer-box-red.log 2>&1"
$process = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d', '/s', '/c', $command) -PassThru -WindowStyle Hidden
$process.WaitForExit(60000)
```

实际输出：`EXIT=1`。新增边界断言有效暴露了 5 个失败：

```text
catalog 未拒绝未 box 的公共 participant（实际返回 catalog）
prepare 未拒绝错误 change identity（实际返回 change）
reprepare 未拒绝错误 change valueType（实际返回 change）
apply 未拒绝错误 change valueType（实际 Future 正常完成）
apply 错误写入值抛出 _TypeError，而不是写入前的 StateError
Some tests failed.
```

### GREEN 与验证

focused GREEN 命令（进程级 60000ms watchdog，输出写入 `logs/settings-transfer-box-green.log`）：

```powershell
$command = "flutter test test/features/settings/application/transfer/settings_transfer_catalog_test.dart --reporter compact > logs/settings-transfer-box-green.log 2>&1"
$process = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d', '/s', '/c', $command) -PassThru -WindowStyle Hidden
$process.WaitForExit(60000)
Write-Host "EXIT=$($process.ExitCode)"
Get-Content -Tail 80 logs/settings-transfer-box-green.log
```

实际输出：

```text
EXIT=0
+19: All tests passed!
```

其余门禁实际输出：

```text
flutter analyze：EXIT=0；No issues found! (ran in 4.6s)
dart run tool/check_import_boundaries.dart：EXIT=0；检查 365 个文件，0 条违规
dart format ...：Formatted 4 files (0 changed)
dart format --output=none --set-exit-if-changed ...：FORMAT_EXIT=0
git diff --cached --check：DIFF_CHECK_EXIT=0
```

初次 fix analyze 曾因新增 fake 的两个未使用可选参数返回 `EXIT=1`；删除这两个无调用默认参数后重跑为上述 `EXIT=0`。

全量测试命令：

```powershell
$command = "flutter test --reporter compact > logs/fltest.log 2>&1"
$process = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d', '/s', '/c', $command) -PassThru -WindowStyle Hidden
$process.WaitForExit(240000)
Write-Host "EXIT=$($process.ExitCode)"
```

实际结果：`EXIT=1`，`1922` 个测试进度中只有既有失败 `test/features/sync/application/sync_server_controller_test.dart:124`：预期 `ClientException`，实际为 `Response`。失败不涉及本轮三个修改文件；Task 2 focused suite 仍为 `19/19` 通过。

### 自审与 concerns

- 本轮没有修改 `settings_transfer_types.dart`、Task 1 document/codec 或任何 Task 3 文件；catalog 的 public 输入仍保持 `Iterable<Object>`，但现在要求调用方显式传入 `SettingsTransferParticipantBox.erase<T>(participant)`。
- 所有 erased payload/change cast 仍集中在 participant box；没有新增 registry、schema fixture 或生产 snapshot 依赖。
- 直接实现公共 `SettingsTransferParticipant<int>` 的 fake 已覆盖 prepare identity、reprepare/apply change valueType、apply 错误写入值；错误路径均在 writer 前失败。
- 全量测试的既有 Sync 失败仍是交付 concern，未在本轮扩大范围修复。

### Fix commit

`848febd632564d9a08f6bfbde82bdb08d94c95e1 fix(settings): 收紧设置传输 participant 类型擦除边界`

post-commit hook 按既有机制将 `pubspec.yaml` 从 `3.62.0+0` bump 到 `3.62.1+0` 并纳入该提交；未手动处理版本文件。

## Fix round 2：隔离正确 valueType 下的错误 writeValue

### 根因与实现

- 复核确认原有错误写入值用的是 `SettingsTransferChange<Object?>`，box 会先因 `valueType != int` 拒绝，未独立覆盖正确 change 类型下的值校验。
- 新增 `SettingsTransferChange<Object?>.erased(...)` application-internal 构造入口，仅额外存储显式 `valueType`；默认 `SettingsTransferChange<T>` 构造器、`final T incoming` 和 `final T writeValue` 保持不变。
- 新回归用例构造 `valueType == int`、`writeValue` 运行时为 `String` 的 change，断言 box 在 writer 前抛出 `StateError` 且 `writeCount` 保持为 0。未修改 box 的 identity 校验、sealed boundary 或 Task 3 文件。

### TDD RED

先用 `SettingsTransferChange<int>` 配合动态错误值尝试隔离路径，命令（进程级 60000ms watchdog）：

```powershell
$command = "flutter test test/features/settings/application/transfer/settings_transfer_catalog_test.dart --reporter compact > logs/settings-transfer-box-red-round2.log 2>&1"
$process = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d', '/s', '/c', $command) -PassThru -WindowStyle Hidden
$process.WaitForExit(60000)
Write-Host "EXIT=$($process.ExitCode)"
```

实际输出为 `EXIT=1`，但失败发生在构造处而非 box：

```text
type 'String' is not a subtype of type 'int'
test/.../settings-transfer_catalog_test.dart:380:28
```

这证明普通 typed 构造器无法生成该 malformed boundary value。随后先写入最终 `.erased` 用法并再次运行同一 focused 命令，实际为 `EXIT=1`，日志明确为：

```text
Error: Couldn't find constructor 'SettingsTransferChange.erased'.
Some tests failed.
```

该 RED 发生在新增内部构造契约尚未实现时，未改动生产 box 行为。

### GREEN 与验证

实现最小 erased 构造入口后重跑 focused 命令（输出写入 `logs/settings-transfer-box-green-round2.log`）：

```powershell
$command = "flutter test test/features/settings/application/transfer/settings_transfer_catalog_test.dart --reporter compact > logs/settings-transfer-box-green-round2.log 2>&1"
$process = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d', '/s', '/c', $command) -PassThru -WindowStyle Hidden
$process.WaitForExit(60000)
Write-Host "EXIT=$($process.ExitCode)"
Get-Content -Tail 80 logs/settings-transfer-box-green-round2.log
```

实际输出：

```text
EXIT=0
+20: All tests passed!
```

提交前实际输出：

```text
dart format 四个 task Dart 文件：Formatted 4 files (0 changed)
dart format --output=none --set-exit-if-changed：FORMAT_EXIT=0
git diff --cached --check：DIFF_CHECK_EXIT=0
flutter analyze：EXIT=0；No issues found! (ran in 5.5s)
```

暂存区只包含：

```text
lib/features/settings/application/transfer/settings_transfer_participant.dart
test/features/settings/application/transfer/settings_transfer_catalog_test.dart
```

### 自审与 concerns

- 默认构造器仍以 `T` 类型暴露并存储 `writeValue`；`.erased` 仅为 application 边界构造待 box 校验的已擦除 change，不是第二套 participant contract 或 registry。
- 新测试的 `valueType` 具体断言为 `int`，错误值路径验证 writer 未被调用；原有错误 change valueType 测试仍保留，分别承担两条失败原因。
- 本轮未重跑全量测试；上一轮报告中的既有 `sync_server_controller_test.dart:124` 失败仍是已知 concern。

### Fix round 2 commit

`6bec4655af0965c946f1712241b12ab1b8040a24 fix(settings): 补齐传输写入值边界回归`

post-commit hook 按既有机制将 `pubspec.yaml` 从 `3.62.1+0` bump 到 `3.62.2+0` 并纳入该提交；未手动处理版本文件。

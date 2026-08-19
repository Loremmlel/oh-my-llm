# Task 1 完成报告：canonical Settings transfer v9 document

## 实现内容

- 新增不可变的 `SettingsTransferDocument`，固定 identifier
  `shikiyuzu-oh-my-llm` 和 `formatVersion = 9`。
- 新增 `SettingsTransferDocumentCodec` 及三种解码结果：成功、不支持版本、格式损坏。
- 实现严格顶层字段校验、v8/v10 版本拒绝、section key 语法校验和 JSON-safe payload 校验。
- 对 map/list 做递归防御性复制并包装为不可修改结构，拒绝非字符串嵌套 key、非 JSON-safe 对象、非有限数字和循环引用。
- 新增 focused tests，覆盖 brief 要求的 round-trip、空 sections、版本边界、malformed 输入、JSON safety 和防御性拷贝场景。

## 文件

本任务新增文件：

- `lib/features/settings/domain/models/transfer/settings_transfer_document.dart`
- `lib/features/settings/domain/models/transfer/settings_transfer_document_codec.dart`
- `test/features/settings/domain/models/transfer/settings_transfer_document_codec_test.dart`

按 brief 保持未修改：`settings_export_data.dart`、`settings_export_codec.dart` 及其测试。

## TDD RED

执行命令：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/settings/domain/models/transfer/settings_transfer_document_codec_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-document-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 120 logs/settings-transfer-document-red.log
if ($TestExit -eq 0) { throw '预期 v9 document 类型尚不存在，red 却通过' }
```

实际结果：`EXIT=1`。失败原因为预期的新生产文件尚不存在，例如：

```text
Error when reading 'lib/features/settings/domain/models/transfer/settings_transfer_document.dart': 系统找不到指定的文件。
Error when reading 'lib/features/settings/domain/models/transfer/settings_transfer_document_codec.dart': 系统找不到指定的文件。
Undefined name 'SettingsTransferDocument'.
Undefined name 'SettingsTransferDocumentCodec'.
```

该 RED 是新类型/文件缺失导致的有效失败，不涉及 native-assets 或既有测试。

## TDD GREEN

执行命令：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/settings/domain/models/transfer/settings_transfer_document_codec_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-document-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 120 logs/settings-transfer-document-green.log
if ($TestExit -ne 0) { exit $TestExit }
```

实现后首次 GREEN 和提交后的 fresh GREEN 均为：

```text
EXIT=0
...
00:01 +9: All tests passed!
```

提交后最后一次 focused test 使用 `TEST_EXIT=0`，9 个用例全部通过。日志：
`logs/settings-transfer-document-red.log`、`logs/settings-transfer-document-green.log`。

## 其他验证

- `flutter analyze`：`EXIT=0`，实际输出 `No issues found! (ran in 8.6s)`。日志：`logs/settings-transfer-document-analyze.log`。
- `dart run tool/check_import_boundaries.dart`：`EXIT=0`，实际输出 `检查 362 个文件，0 条违规`。日志：`logs/settings-transfer-document-boundaries.log`。
- `dart format --output=none --set-exit-if-changed`：`FORMAT_EXIT=0`，3 个任务 Dart 文件均已格式化。
- `git diff --check`：`DIFF_CHECK_EXIT=0`。
- 提交前 `git diff --cached --name-only` 精确列出 brief 的三个任务文件。
- 最终工作树干净：`git status --short --branch` 仅显示当前分支，无未提交改动。

## Commit

- 提交信息：`feat(settings): 建立设置传输 v9 文档`
- 最终 commit：`bcd3f62ed5229132f887f54307dfb010f00050f3`
- post-commit hook 按仓库约定将版本从 `3.60.6+0` bump 到 `3.61.0+0`，因此 amend 后 commit 还包含 `pubspec.yaml` 的版本变更；任务文件本身仍只有上述三个新增文件。

## 自审

- document 只依赖 `equatable` 与 `dart:convert`，没有 participant、application 或 Sync imports。
- codec 只处理 canonical 顶层 envelope 和 JSON-safe section，不查注册表、不解码 participant payload。
- 顶层必须恰好包含 `identifier`、`formatVersion`、`sections`；错误 identifier、非整数版本、非 map sections 和额外字段均返回 `Malformed`。
- 整数版本不是 9 时返回 `UnsupportedVersion` 并保留原始版本号。
- map/list 的嵌套结构在构造时完成复制和不可变包装，`toJson()` 返回的顶层和嵌套结构均不能由调用方修改。

## Concerns

- 无阻塞项。brief 要求校验 section key syntax 但未单独给出正则；当前采用稳定的 ASCII lower-camel 规则 `[a-z][A-Za-z0-9]*`，已知 participant key 均符合该规则。若后续 registry 明确允许连字符、下划线或其他 wire key 语法，需要同步调整 codec 与该 focused test。
- 版本 bump 是仓库 post-commit hook 的既定行为，不是本任务手动扩大暂存范围。

## Fix round 1 报告

### 审查 ruling 与改动

本轮按 controller ruling 将 ASCII lower-camel `[a-z][A-Za-z0-9]*` 固化为 stable key rule：

- 在 `settings_transfer_document.dart` 和 `settings_transfer_document_codec.dart` 的 key 校验函数上增加简体中文注释，明确首字符必须是小写英文字母，后续只能是英文字母或数字；下划线、连字符或大写首字母必须经过显式规格和 formatVersion 变更。
- 在 focused test 中新增未知但语法合法的 `futureParticipant42` key，断言 codec 接受并保留该 key。
- 扩充非法边界断言，覆盖大写首字母 `UpperCamel`、下划线 `snake_case` 和连字符 `dash-key`。
- codec 仍只做顶层结构、key grammar 与 JSON-safe 校验，没有 catalog 或 participant imports，也不查询 catalog。

本轮实际改动仍只涉及三个任务 Dart 文件：

- `lib/features/settings/domain/models/transfer/settings_transfer_document.dart`
- `lib/features/settings/domain/models/transfer/settings_transfer_document_codec.dart`
- `test/features/settings/domain/models/transfer/settings_transfer_document_codec_test.dart`

### 测试覆盖与 TDD 说明

新增测试覆盖：

- 未知 lower-camel key 可被 codec 接受，证明 codec 不依赖注册表；
- 大写首字母、下划线、连字符以及原有空白、斜杠、数字首字符均被拒绝；
- 原有 9 个 v9 document 场景继续保留。

本轮审查 finding 是“缺少已批准 grammar 的注释与行为证据”，不是运行时接受/拒绝逻辑错误；在新增测试之前，现有实现已经接受 `futureParticipant42`，因此该测试基线直接通过，未伪造无效 RED。生产代码本轮只增加契约注释，没有新增运行时行为。

### Fix round 命令与实际输出

新增测试后的 focused baseline：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/settings/domain/models/transfer/settings_transfer_document_codec_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-document-fix-baseline.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 80 logs/settings-transfer-document-fix-baseline.log
if ($TestExit -ne 0) { exit $TestExit }
```

实际输出：

```text
EXIT=0
00:01 +3: 未知但符合 lower-camel 稳定规则的 section key 会被 codec 接受
...
00:01 +10: All tests passed!
```

按 fix brief 执行的 focused GREEN：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/settings/domain/models/transfer/settings_transfer_document_codec_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-document-fix-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 100 logs/settings-transfer-document-fix-green.log
if ($TestExit -ne 0) { exit $TestExit }
```

实际输出：`EXIT=0`，新增合法未知 key 用例和全部原有场景通过，最终显示 `00:01 +10: All tests passed!`。提交后再次 fresh 执行同一 focused GREEN，实际为 `TEST_EXIT=0`、10/10 通过。日志：`logs/settings-transfer-document-fix-baseline.log`、`logs/settings-transfer-document-fix-green.log`。

格式化与暂存区证据：

```powershell
$TransferFiles = @(
  'lib/features/settings/domain/models/transfer/settings_transfer_document.dart',
  'lib/features/settings/domain/models/transfer/settings_transfer_document_codec.dart',
  'test/features/settings/domain/models/transfer/settings_transfer_document_codec_test.dart'
)
dart format $TransferFiles
git add -- $TransferFiles
dart format --output=none --set-exit-if-changed $TransferFiles
git diff --cached --check
git diff --cached --name-only
```

实际输出：

```text
Formatted 3 files (0 changed) in 0.01 seconds.
FORMAT_EXIT=0
DIFF_CHECK_EXIT=0
lib/features/settings/domain/models/transfer/settings_transfer_document.dart
lib/features/settings/domain/models/transfer/settings_transfer_document_codec.dart
test/features/settings/domain/models/transfer/settings_transfer_document_codec_test.dart
```

提交命令与结果：

```powershell
git commit -m "fix(settings): 固化设置传输 section key 规则"
```

实际输出包含：

```text
[post-commit] Version bumped: 3.61.0+0 -> 3.61.1+0 | fix(settings): 固化设置传输 section key 规则
```

post-commit amend 后最终 HEAD 为 `4304248d61aaa6560874e590c0aefd33116170cd`，最终版本为 `3.61.1+0`。提交后再次执行 `dart format --output=none --set-exit-if-changed` 得到 `FORMAT_EXIT=0`，再次执行 `git diff --cached --check` 得到 `CACHED_DIFF_CHECK_EXIT=0`；工作树干净。

### Fix round 其他验证

- `flutter analyze`：`ANALYZE_EXIT=0`，实际输出 `No issues found! (ran in 4.9s)`。日志：`logs/settings-transfer-document-fix-analyze.log`。
- 最终 commit 的任务改动为 3 个 Dart 文件；`pubspec.yaml` 仅由仓库 post-commit hook 自动 bump 并纳入 amend commit。

### Fix round concerns

- 无未解决 concern。stable key grammar 已在实现注释、合法未知 key 测试和非法边界测试中形成一致契约。

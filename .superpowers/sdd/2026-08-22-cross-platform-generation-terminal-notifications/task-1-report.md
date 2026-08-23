# Task 1 报告：只新增终态收据，不改变既有投递行为

状态：DONE（提交 `46c2b952cea3b00ef9573687c8ff2418aa876d9d`，分支 `feat/cross-platform-generation-notifications`）

## 实现摘要

新增三个文件，未修改任何既有文件：

- `lib/features/chat/application/generation/chat_generation_terminal_notification.dart`
  - `enum ChatGenerationTerminalKind`（succeeded / emptyReply / failed / persistenceFailed / foregroundProtectionTimedOut）
  - `enum ChatGenerationTerminalFailureKind`（none / emptyReply / network / timeout / authentication / authorization / rateLimited / server / invalidOutput / persistence / foregroundProtection / unknown）
  - `final class ChatGenerationTerminalReceipt extends Equatable`：字段与事件键按计划 5.1；构造 invariant 全部用 `assert` 实现（session ID 32 位小写十六进制、generationId 1..Long 上限、conversationId trim 后 1..256 且无控制字符、双计数非负、终态/失败分类配对约束）；`eventKey = 'v1:<session>:<generation>:<kind.name>'`
  - 纯函数 `projectChatGenerationTerminalReceipt(...)`：按 snapshot.phase 投影；非终态与 cancelled 返回 null；succeeded 从完整 `ChatGenerationSuccess` outcome 用 `countChatWords` 重算计数（不信任节流 fallback）；emptyReply/failed/persistenceFailed 沿用传入的最后安全 counts；失败分类只读既有安全类型信息（output rule 哨兵、Timeout/Socket 含包装 cause、`ChatGenerationException.statusCode` 的 401/403/429/5xx），其余统一 unknown，绝不检查文本 substring
- `lib/features/chat/application/ports/chat_generation_terminal_notifications.dart`
  - `abstract interface class ChatGenerationTerminalNotifications`（`report(receipt)` / `dispose()`），按计划 3.3；不新增 provider（provider 归 Task 2）
- `test/features/chat/application/generation/chat_generation_terminal_notification_test.dart`
  - 覆盖 brief 全部 11 个 RED 用例 + 1 个配对 invariant 用例，共 12 个测试

## 测试结果（RED/GREEN）

- RED：`logs/terminal-receipt-red.log`，`EXIT=1`，编译失败（新类型缺失），属合法 RED
- GREEN：`logs/terminal-receipt-green.log`，`EXIT=0`，12/12 通过
- 既有契约回归：`logs/terminal-receipt-existing-green.log`，`EXIT=0`，`chat_generation_notification_test.dart` 21/21 通过（ongoing projector / cleanup / fail 契约未被改动）
- 静态检查：`logs/terminal-receipt-analyze.log`，`flutter analyze` No issues found
- 架构门禁：`logs/terminal-receipt-boundary.log`，`dart run tool/check_import_boundaries.dart` 394 文件 0 违规
- 格式：`dart format --output=none --set-exit-if-changed` 通过；提交前已 `dart format` 三个新文件

## 遇到的问题

1. **反斜杠-u 类转义在写文件时被工具层解释成真实 NUL 控制字节**：测试文件中的 `a<u-escape>0000b` 曾落盘为 `a<0x00>b`，Dart 编译会失败。已改用 `String.fromCharCode(0)` 在运行时构造 NUL 字符，源文件不再含转义；并用 perl 字节级扫描确认全部新增文件无残留控制字节。实现侧控制字符判断改用 `codeUnitAt` 与 `0x20`/`0x7f` 十六进制字面量，避免同类问题。
2. **const 构造器无法承载运行时 invariant**：计划 5.1 示意 `const ChatGenerationTerminalReceipt(...)`，但 `assert` 内调用正则 `hasMatch` 与私有函数，const 上下文编译报错（"Not a constant expression"）。已将构造器改为非 const（全项目无 const 实例化点，不影响使用）；计划其余内容未变。
3. **首个测试命令 60s 工具超时移入后台**：冷编译约 48s，非挂起；未触发 stale 进程清理，后续运行约 3s 完成。
4. **自测断言失误**：`event key 格式固定且不携带正文` 起初断言 event key 不含 '5'/'3'，但固定测试 session `000102030405060708090a0b0c0d0e0f` 本身就含这些数字，断言恒假。改为用两位计数（88/99）断言不泄漏，并核对 session 十六进制不含 '88'/'99' 子串。

## 自审发现

- 失败分类顺序与既有 `summarizeChatGenerationNotificationError` 一致（哨兵 -> timeout -> socket -> statusCode），保持行为等价；`foregroundProtectionTimedOut` 终态不由本投影函数从 snapshot 产生（无对应 phase），仅由构造 invariant 支持配对，由 Task 3 超时路径直接构造，符合计划。
- 防御性处理：succeeded 终态缺 outcome 或类型不符时返回 null（不写错误计数）；failed 终态缺 outcome 时 failureKind 退化为 unknown；均不抛异常，符合通知链路 fail-open 取向。
- 本提交只新增文件（git show 仅 3 个新文件 + post-commit hook 自动 bump 的 `pubspec.yaml`），未触碰 ongoing projector、coordinator 或 foreground port，Task 3 再原子收窄。
- 停止条件均未触发：收据不保存原始错误或回复文本；五类终态可从 snapshot.phase + outcome 完整区分。

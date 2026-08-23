### Task 1：只新增终态收据，不改变既有投递行为

**文件**

- 新增 `lib/features/chat/application/generation/chat_generation_terminal_notification.dart`
- 新增 `lib/features/chat/application/ports/chat_generation_terminal_notifications.dart`
- 新增 `test/features/chat/application/generation/chat_generation_terminal_notification_test.dart`

**RED 测试**

- `成功终态生成安全计数收据`
- `成功终态从完整 outcome 计数而不使用节流 fallback`
- `空回复使用独立终态与安全分类`
- `最终失败按异常类型映射安全分类`
- `HTTP 401 403 429 和 5xx 只读取 ChatGenerationException.statusCode`
- `缺少 statusCode 且类型不可识别时统一退化为 unknown`
- `持久化失败不归类为普通生成失败`
- `取消和非终态不生成收据`
- `收据拒绝非法 session generation ID 会话 ID 与负计数`
- `不同 session 的相同 generation 生成不同 event key`
- `event key 格式固定且不携带正文`

命令：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/chat/application/generation/chat_generation_terminal_notification_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/terminal-receipt-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/terminal-receipt-red.log
```

工具超时 60000ms。RED 必须因新类型/行为缺失失败。

**GREEN**

- 实现第 5.1 节类型、invariant 和纯映射。
- 不修改 ongoing projector、coordinator 或 foreground port；本提交只是可独立编译的新增能力，既有 terminal cleanup/fail 行为必须保持全绿。projector 收窄与 coordinator 迁移在 Task 3 原子完成。
- 同命令写 `logs/terminal-receipt-green.log` 并达到 `EXIT=0`。
- 另运行既有 `test/features/chat/application/generation/chat_generation_notification_test.dart`，日志写入 `logs/terminal-receipt-existing-green.log`；证明新增收据尚未改变 ongoing projector、cleanup 或 fail 契约。

**停止条件**

- 需要把原始错误或回复文本保存在 receipt。
- 无法从现有 snapshot/outcome 区分五类终态。


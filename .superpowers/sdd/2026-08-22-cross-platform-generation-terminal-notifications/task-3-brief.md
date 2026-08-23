### Task 3：coordinator 接入与前台服务端口瘦身

**文件**

- 修改 `lib/app/composition/chat_generation_notification_coordinator.dart`
- 修改 `lib/features/chat/application/generation/chat_generation_notification.dart`
- 修改 `lib/features/chat/application/ports/chat_generation_foreground_service.dart`
- 修改 `test/app/composition/chat_generation_notification_coordinator_test.dart`
- 修改 `test/features/chat/application/generation/chat_generation_notification_test.dart`
- 修改 `lib/app/platform/android_chat_generation_foreground_service.dart`
- 修改 `lib/app/platform/noop_chat_generation_foreground_service.dart`
- 修改 `test/app/platform/android_chat_generation_foreground_service_test.dart`
- 修改 `test/app/platform/noop_chat_generation_foreground_service_test.dart`
- 修改 `test/app/composition/chat_generation_foreground_service_bindings_test.dart`
- 修改 `test/integration/chat_generation_notification_integration_test.dart`

**RED 测试**

- `成功先清理 ongoing 再报告终态`
- `三次 cleanup channel timeout 与退避使 report 最晚在 cleanup 开始后 7 秒执行`
- `空回复失败和持久化失败都清理 ongoing`
- `取消只清理不报告`
- `中间重试不清理也不报告`
- `成功终态使用完整 outcome 计数而 timeout 使用 context 最后安全计数`
- `保护超时只报告且不调用 remove 或停止生成`
- `保护超时后真正终态仍报告且不重复清理`
- `terminal report 失败不毒化 coordinator`
- `尚未入队的旧 token terminal 和 timeout 被拒绝`
- `token1 terminal 入队后 token2 启动仍按 start1 cleanup1 report1 start2 顺序完成`
- `token1 ACK 迟到只修改 token1 context 不毒化 token2`
- `ongoing warm 与 pending 点击仍转发到现有 openConversation 回调`

**GREEN**

- 严格按第 6 节调整。
- coordinator provider 读取 Task 2 的 `chatGenerationTerminalNotificationsProvider` 与 notification session provider；不得在构造函数现场生成第二个 session。此时 adapter 安全默认为 no-op，直到 Task 9 一次性装配真实平台 adapter。
- 在同一 Task 原子收窄 ongoing projector；不得先提交“projector 拒绝 terminal、coordinator 仍调用 projector”的行为断层。
- 删除 `fail` 端口职责与旧 LOW terminal 测试，不保留 deprecated shim；保留并回归 ongoing 的 open/pending 职责。
- 运行：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/app/composition/chat_generation_notification_coordinator_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/terminal-coordinator-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/terminal-coordinator-green.log
```

工具超时 60000ms。

**停止条件**

- 需要修改 `ChatGenerationRun` 或创建第二套 terminal flag。
- 无法保证 durable save 后才收到真正终态。


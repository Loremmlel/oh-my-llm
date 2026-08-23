### Task 5：Android Kotlin HIGH 通知与设置

**文件**

- 按第 7.1 节重命名 protocol/channel/test
- 修改 `lib/app/platform/android_chat_generation_platform_bridge.dart`，与 Kotlin 同时切换最终 channel 名
- 新增 `ChatGenerationTerminalNotification.kt`
- 修改 `ChatGenerationForegroundService.kt`
- 修改 `MainActivity.kt`
- 修改 `chat_generation_strings.xml`

**RED 测试**

- `终态渠道配置为 HIGH 且不是 silent`
- `前台渠道仍为 LOW 且 silent`
- `终态通知 ID 不与 4101 冲突`
- `每个终态 PendingIntent request code 与 data URI 唯一`
- `终态通知构造同时使用 private 和固定 public version`
- `Kotlin 只校验 timeout activation payload 类型与长度不解析 JSON`
- `timeout callback 未受理时选择 HIGH fallback`
- `timeout fallback 固定使用通知 ID 与 request code 4200`
- `timeout fallback 原样复用 Dart session scoped payload`
- `ongoing content intent 仍打开对应会话`
- `首次设置状态查询会创建终态 channel 且不重建已有 channel`
- `通知禁用或终态渠道为 NONE 时返回 disabled`
- `打开设置 Intent 只使用当前 package`

**GREEN**

- 实现第 7 节协议、HIGH channel、timeout fallback 和设置。
- 不修改 Manifest，不引入 Robolectric。
- 运行：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
.\android\gradlew.bat -p android :app:testDebugUnitTest 2>&1 | Out-File -Encoding utf8 logs/android-terminal-notification-test.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/android-terminal-notification-test.log
```

命令级硬超时 120000ms。仓库 module 为 `:app`，使用上述确定 task，不在实施时重新选择测试框架。

**停止条件**

- 只能升级已有 LOW channel 才能得到横幅。
- Kotlin 需要参与真正 generation outcome 判定。
- 需要重复弹 POST_NOTIFICATIONS 权限。


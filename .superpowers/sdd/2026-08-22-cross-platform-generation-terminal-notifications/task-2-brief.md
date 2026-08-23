### Task 2：注意力、基础端口与默认终态通知深模块

**文件**

- 新增 `lib/app/attention/app_attention_state.dart`
- 新增 `lib/app/attention/app_window.dart`
- 新增 `lib/app/attention/app_attention_observer.dart`
- 新增 `lib/app/notifications/chat_generation_terminal_notification_adapter.dart`
- 新增 `lib/app/notifications/chat_generation_notification_session.dart`
- 新增 `lib/app/notifications/default_chat_generation_terminal_notifications.dart`
- 新增 `lib/app/platform/noop_chat_generation_terminal_notification_adapter.dart`
- 新增 `lib/app/platform/noop_app_window.dart`
- 新增 `lib/features/settings/application/ports/system_notification_settings.dart`
- 新增 `test/app/attention/app_attention_observer_test.dart`
- 新增 `test/app/notifications/chat_generation_notification_session_test.dart`
- 新增 `test/app/notifications/chat_generation_notification_payload_test.dart`
- 新增 `test/app/notifications/default_chat_generation_terminal_notifications_test.dart`

**RED 测试**

- `前台聚焦且查看对应会话时抑制通知`
- `查看其他会话时展示通知`
- `非聊天页面时展示通知`
- `Windows 窗口失焦时展示通知`
- `同一收据重复报告时只展示一次`
- `被抑制的收据不会在失焦后重放`
- `保护超时后仍允许真正终态`
- `平台初始化和展示失败均不向调用者抛出`
- `report 在初始化完成前到达时等待同一个 start future`
- `展示失败不完成 report 去重且后续重复报告可重试`
- `固定 event key 生成固定通知 ID`
- `不同进程 session 的相同终态不会复用通知 ID 向量`
- `payload 只包含三个允许字段`
- `超长 控制字符 额外字段 未知版本和 malformed payload 被忽略`
- `hot 与 pending activation 只导航一次`
- `空闲 scheduler 会主动请求导航帧`
- `导航排队后 dispose 不执行 openChat`
- `窗口恢复或导航失败后再次点击可以重试`
- `已删除会话回退聊天根页`
- `会话存在判断在导航帧读取而不捕获启动期空列表`
- `detached 初值在首个真实注意力快照前选择展示`
- `迟到的初始焦点查询不覆盖较新的 focus event`
- `completed 去重集合和 in-flight 集合都有上限`
- `dispose 幂等并取消激活订阅`

**GREEN**

- 完成第 5.2–5.5 节。
- 定义 `chatGenerationTerminalNotificationsProvider`、`chatGenerationTerminalNotificationAdapterProvider` 与 notification session provider；adapter provider 在平台 composition 完成前固定绑定 no-op，不能抛“未绑定”异常。
- settings port/provider 在本 Task 创建但不接 UI，为 Task 4/8/9 提供可编译 seam。
- provider dispose 调深模块 dispose。
- 本 Task 只完成深模块与 provider 定义，不修改 `lib/app/app.dart`；根部 eager 装配统一留给 Task 9，避免两次临时接线。
- 单文件测试分别写 `logs/app-attention-green.log`、`logs/terminal-notifications-green.log`，工具超时 60000ms。

**停止条件**

- 抑制判断需要 presentation controller。
- adapter 必须理解 generation outcome。


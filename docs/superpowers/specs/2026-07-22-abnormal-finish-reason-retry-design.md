# 异常 finish_reason 自动重试 设计文档

**日期**：2026-07-22
**状态**：已确认

## Context

当前自动重试机制只在流式请求失败（网络错误、SSE 异常）时触发重试。模型的 `finish_reason` 值不影响重试逻辑——即使返回 `length`（token 用完）或 `content_filter`（内容过滤）等异常值，系统也不会自动重试。用户希望在自动重试设置中新增一个选项，让异常的 `finish_reason` 也能触发自动重试。

## 设计决策

1. **正常值定义**：`stop` 和 `tool_calls` 为正常值，其他所有值均为异常
2. **依赖对话级开关**：只有对话级自动重试开启时才生效
3. **复用现有重试配置**：间隔模式、次数限制等全部复用，不新增独立配置
4. **拦截点**：在 `completeWithSuccess` 中检测异常 `finish_reason`，走失败路径触发重试

## 数据模型

### `AutoRetrySettings` 新增字段

```dart
/// 当 finish_reason 不是正常值（stop、tool_calls）时是否自动重试。
final bool retryOnAbnormalFinishReason; // 默认 false
```

- `toJson()` 新增 `'retryOnAbnormalFinishReason'` key
- `fromJson()` 旧数据缺失此 key 时回退为 `false`
- `copyWith()` 新增 `bool? retryOnAbnormalFinishReason` 和 `bool clearRetryOnAbnormalFinishReason`
- `props` 新增此字段

### 工具函数

在 `auto_retry_settings.dart` 中新增：

```dart
const _normalFinishReasons = {'stop', 'tool_calls'};

bool isAbnormalFinishReason(String? finishReason) {
  if (finishReason == null) return false;
  return !_normalFinishReasons.contains(finishReason);
}
```

## UI

在设置页"其他"→"自动重试"卡片中，在现有控件（模式选择、间隔、次数）**之后**新增 `SwitchListTile`：

- 标题：异常 finish_reason 重试
- 副标题：当模型返回的 finish_reason 不是 stop 或 tool_calls 时自动重试
- 绑定：`settings.retryOnAbnormalFinishReason`

## 核心逻辑

### 参数传递

`streamAssistantReply` 新增 `bool retryOnAbnormalFinishReason` 参数，由 `_sendWithOptionalAutoRetry` 从 `autoRetrySettingsProvider` 读取并传入。`sendMessageWithAutoRetry` 也需要透传此参数。

### `completeWithSuccess` 中的拦截

在空回复检查之后、正常落盘之前，新增异常 finish_reason 检查：

```dart
if (retryOnAbnormalFinishReason &&
    isAbnormalFinishReason(streamingReply.finishReason)) {
  // 保留占位节点，设置错误消息
  final abnormalTree = resolveMessageTreeState(streamingConversation);
  final nextTree = replaceAssistantMessageInTree(
    treeState: abnormalTree,
    assistantMessageId: assistantMessage.id,
    nextContent: applyOutputProcessing(streamingReply.content),
    nextReasoningContent: streamingReply.reasoningContent,
    isStreaming: false,
    finishReason: streamingReply.finishReason,
  );
  final abnormalConversation = mergeStreamingResultIntoActive(
    streamingConversation: streamingConversation,
    messageNodes: nextTree.nodes,
    selectedChildByParentId: nextTree.selections,
  );
  state = state.copyWith(
    conversations: replaceConversation(abnormalConversation),
    conversationSummaries: replaceOrAddSummary(
      state.conversationSummaries,
      summaryFromConversation(abnormalConversation),
    ),
    isStreaming: false,
    errorMessage: '模型返回异常停止原因（finish_reason: ${streamingReply.finishReason}），正在自动重试...',
    errorMessageAssistantId: assistantMessage.id,
    clearStreamingReply: true,
    incrementHistoryRevision: true,
  );
  saveConversation(abnormalConversation);
  completeActiveStreaming(null);
  clearActiveStreamingSession();
  return;
}
```

`completeActiveStreaming(null)` 使 `sendMessageWithAutoRetry` 的重试循环检测到 `result == null`，从而继续重试。

### 错误消息

格式：`"模型返回异常停止原因（finish_reason: {value}），正在自动重试..."`

## 修改文件清单

| 文件 | 改动 |
|------|------|
| `lib/features/settings/domain/models/auto_retry_settings.dart` | 新增 `retryOnAbnormalFinishReason` 字段、`isAbnormalFinishReason` 函数 |
| `lib/features/settings/presentation/widgets/tab/other_settings_tab.dart` | 新增 `SwitchListTile` |
| `lib/features/chat/application/chat_sessions_controller_streaming.dart` | `streamAssistantReply` 新增参数、`completeWithSuccess` 新增拦截逻辑、`sendMessageWithAutoRetry` 透传参数 |
| `lib/features/chat/application/chat_sessions_controller.dart` | `_sendWithOptionalAutoRetry` 读取新设置并传参 |
| `test/features/settings/domain/models/auto_retry_settings_test.dart` | 新增字段序列化/反序列化测试 |
| `test/features/chat/application/chat_sessions_controller_streaming_test.dart` | 新增异常 finish_reason 重试测试 |

## 验证方式

1. 设置页面：开关出现且切换后持久化
2. 功能：开启对话级自动重试 + 全局异常 finish 重试 → 发送消息 → 模型返回 `length` → 自动重试
3. 功能：关闭对话级自动重试 → 模型返回 `length` → 不重试
4. 功能：开启自动重试但关闭异常 finish 重试 → 模型返回 `length` → 不重试（保持原有行为）
5. 功能：`stop` 和 `tool_calls` 不触发重试
6. 数据兼容：旧版本存储的设置无 `retryOnAbnormalFinishReason` key → 默认为 `false`
7. 运行 `flutter test` 全量通过

# 异常 finish_reason 自动重试 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在自动重试设置中新增"异常 finish_reason 重试"选项，当流式回复的 finish_reason 不是正常值（stop、tool_calls）时自动触发重试。

**Architecture:** 在 `AutoRetrySettings` 数据模型中新增 `retryOnAbnormalFinishReason` 布尔字段，通过 `streamAssistantReply` 参数传入流式处理闭包，在 `completeWithSuccess` 中拦截异常 finish_reason 并走失败路径触发现有重试循环。

**Tech Stack:** Flutter / Dart / Riverpod / SharedPreferences

## Global Constraints

- 注释使用**简体中文**，`///` 用于 doc 注释，`//` 用于行间注释
- 禁止 `part` / `part of`
- `fromJson` 旧数据缺失字段时回退为默认值
- 测试命令：`flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log`
- 提交使用 Bash：`git commit -m "feat: ..."`

---

### Task 1: 数据模型 — AutoRetrySettings 新增字段 + isAbnormalFinishReason 函数

**Files:**
- Modify: `lib/features/settings/domain/models/auto_retry_settings.dart`
- Test: `test/features/settings/domain/models/auto_retry_settings_test.dart`

**Interfaces:**
- Produces: `AutoRetrySettings.retryOnAbnormalFinishReason` (bool, 默认 false)；`AutoRetrySettings.copyWith(retryOnAbnormalFinishReason: ..., clearRetryOnAbnormalFinishReason: ...)`；`isAbnormalFinishReason(String?) → bool`

- [ ] **Step 1: 写 isAbnormalFinishReason 的失败测试**

在 `test/features/settings/domain/models/auto_retry_settings_test.dart` 末尾新增：

```dart
group('isAbnormalFinishReason', () {
  test('stop 不算异常', () {
    expect(isAbnormalFinishReason('stop'), isFalse);
  });

  test('tool_calls 不算异常', () {
    expect(isAbnormalFinishReason('tool_calls'), isFalse);
  });

  test('length 算异常', () {
    expect(isAbnormalFinishReason('length'), isTrue);
  });

  test('content_filter 算异常', () {
    expect(isAbnormalFinishReason('content_filter'), isTrue);
  });

  test('null 不算异常', () {
    expect(isAbnormalFinishReason(null), isFalse);
  });

  test('未知值算异常', () {
    expect(isAbnormalFinishReason('unknown_reason'), isTrue);
  });
});
```

- [ ] **Step 2: 运行测试验证失败**

```powershell
flutter test --reporter compact test/features/settings/domain/models/auto_retry_settings_test.dart 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

Expected: FAIL — `isAbnormalFinishReason` 未定义

- [ ] **Step 3: 实现 isAbnormalFinishReason 函数**

在 `lib/features/settings/domain/models/auto_retry_settings.dart` 中，`AutoRetrySettings` 类之后、文件末尾之前新增：

```dart
/// finish_reason 的正常值：模型正常完成或请求工具调用。
const normalFinishReasons = {'stop', 'tool_calls'};

/// 判断 [finishReason] 是否为异常值。
///
/// `stop` 和 `tool_calls` 为正常值，`null` 视为正常（流未结束时为 null），
/// 其余所有值（如 `length`、`content_filter`）均视为异常。
bool isAbnormalFinishReason(String? finishReason) {
  if (finishReason == null) return false;
  return !normalFinishReasons.contains(finishReason);
}
```

- [ ] **Step 4: 运行测试验证通过**

```powershell
flutter test --reporter compact test/features/settings/domain/models/auto_retry_settings_test.dart 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

Expected: PASS

- [ ] **Step 5: 写 retryOnAbnormalFinishReason 字段的失败测试**

在 `test/features/settings/domain/models/auto_retry_settings_test.dart` 的 `AutoRetrySettings` group 中新增：

```dart
test('copyWith clearRetryOnAbnormalFinishReason 重置为默认值 false', () {
  const settings = AutoRetrySettings(retryOnAbnormalFinishReason: true);
  final cleared = settings.copyWith(clearRetryOnAbnormalFinishReason: true);
  expect(cleared.retryOnAbnormalFinishReason, isFalse);
});

test('fromJson 缺失 retryOnAbnormalFinishReason 使用默认值 false', () {
  final settings = AutoRetrySettings.fromJson({
    'maxJitterSeconds': 15,
    'maxRetryCount': 0,
    'retryMode': 'perMinuteWindow',
  });
  expect(settings.retryOnAbnormalFinishReason, isFalse);
});

test('retryOnAbnormalFinishReason round-trip', () {
  const settings = AutoRetrySettings(retryOnAbnormalFinishReason: true);
  final restored = AutoRetrySettings.fromJson(settings.toJson());
  expect(restored.retryOnAbnormalFinishReason, isTrue);
  expect(restored, settings);
});
```

- [ ] **Step 6: 实现 retryOnAbnormalFinishReason 字段**

在 `lib/features/settings/domain/models/auto_retry_settings.dart` 的 `AutoRetrySettings` 类中：

1. 构造函数新增参数 `this.retryOnAbnormalFinishReason = false`
2. 新增字段：

```dart
/// 当 finish_reason 不是正常值（stop、tool_calls）时是否自动重试。
final bool retryOnAbnormalFinishReason;
```

3. `copyWith` 新增：

```dart
bool? retryOnAbnormalFinishReason,
bool clearRetryOnAbnormalFinishReason = false,
```

方法体中新增：

```dart
retryOnAbnormalFinishReason: clearRetryOnAbnormalFinishReason
    ? false
    : retryOnAbnormalFinishReason ?? this.retryOnAbnormalFinishReason,
```

4. `toJson` 新增：`'retryOnAbnormalFinishReason': retryOnAbnormalFinishReason,`
5. `fromJson` 新增：`retryOnAbnormalFinishReason: (json['retryOnAbnormalFinishReason'] as bool?) ?? false,`
6. `props` 新增：`retryOnAbnormalFinishReason,`

- [ ] **Step 7: 运行测试验证通过**

```powershell
flutter test --reporter compact test/features/settings/domain/models/auto_retry_settings_test.dart 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

Expected: PASS

- [ ] **Step 8: 提交**

```bash
git add lib/features/settings/domain/models/auto_retry_settings.dart test/features/settings/domain/models/auto_retry_settings_test.dart
git commit -m "feat: 新增 retryOnAbnormalFinishReason 字段和 isAbnormalFinishReason 函数"
```

---

### Task 2: 设置页 UI — SwitchListTile

**Files:**
- Modify: `lib/features/settings/presentation/widgets/tab/other_settings_tab.dart`

**Interfaces:**
- Consumes: `AutoRetrySettings.retryOnAbnormalFinishReason` (from Task 1)

- [ ] **Step 1: 在自动重试卡片末尾新增 SwitchListTile**

在 `other_settings_tab.dart` 的"自动重试" `SettingsSectionCard` 的 `child` Column 中，在 `_AutoRetryNumberField`（最大重试次数）之后新增：

```dart
const SizedBox(height: 16),
SwitchListTile(
  contentPadding: EdgeInsets.zero,
  title: const Text('异常 finish_reason 重试'),
  subtitle: const Text(
    '当模型返回的 finish_reason 不是 stop 或 tool_calls 时自动重试',
  ),
  value: settings.retryOnAbnormalFinishReason,
  onChanged: (value) {
    ref
        .read(autoRetrySettingsProvider.notifier)
        .save(settings.copyWith(retryOnAbnormalFinishReason: value));
  },
),
```

- [ ] **Step 2: 运行分析确认无错误**

```powershell
flutter analyze
```

Expected: No issues found

- [ ] **Step 3: 提交**

```bash
git add lib/features/settings/presentation/widgets/tab/other_settings_tab.dart
git commit -m "feat: 在自动重试设置中新增异常 finish_reason 重试开关"
```

---

### Task 3: 核心逻辑 — completeWithSuccess 拦截异常 finish_reason

**Files:**
- Modify: `lib/features/chat/application/chat_sessions_controller_streaming.dart`
- Modify: `lib/features/chat/application/chat_sessions_controller.dart`

**Interfaces:**
- Consumes: `isAbnormalFinishReason` (from Task 1)；`AutoRetrySettings.retryOnAbnormalFinishReason`
- Produces: `streamAssistantReply` 新增 `retryOnAbnormalFinishReason` 参数；`sendMessageWithAutoRetry` 新增 `retryOnAbnormalFinishReason` 参数

- [ ] **Step 1: 在 streamAssistantReply 签名中新增参数**

在 `chat_sessions_controller_streaming.dart` 的 `streamAssistantReply` 方法中，新增可选命名参数：

```dart
bool retryOnAbnormalFinishReason = false,
```

添加在 `String appliedCheckpointTitle = '',` 之后。

- [ ] **Step 2: 在 completeWithSuccess 中新增异常 finish_reason 拦截**

在 `chat_sessions_controller_streaming.dart` 的 `completeWithSuccess` 中，在空回复检查块（`if (_isEmptyStreamingReply(...))` 块的 `return;` 之后）、输出正则处理之前新增：

```dart
// 异常 finish_reason：如果启用且 finish_reason 不是正常值，走失败路径触发重试。
if (retryOnAbnormalFinishReason &&
    isAbnormalFinishReason(streamingReply.finishReason)) {
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
    errorMessage:
        '模型返回异常停止原因（finish_reason: ${streamingReply.finishReason}），正在自动重试...',
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

- [ ] **Step 3: 在 sendMessageWithAutoRetry 中新增参数并透传**

1. `sendMessageWithAutoRetry` 签名新增：

```dart
this.retryOnAbnormalFinishReason = false,
```

添加在 `RetryMode retryMode = RetryMode.perMinuteWindow,` 之后。

2. 在 `sendMessageWithAutoRetry` 中调用 `streamAssistantReply` 时传入：

```dart
retryOnAbnormalFinishReason: retryOnAbnormalFinishReason,
```

- [ ] **Step 4: 在 _sendWithOptionalAutoRetry 中读取设置并传参**

在 `chat_sessions_controller.dart` 的 `_sendWithOptionalAutoRetry` 中：

1. `sendMessageWithAutoRetry` 调用新增参数：

```dart
retryOnAbnormalFinishReason: autoRetrySettings.retryOnAbnormalFinishReason,
```

2. `streamAssistantReply` 调用无需改动——不在自动重试模式下时，`retryOnAbnormalFinishReason` 保持默认 `false`。

- [ ] **Step 5: 运行分析确认无错误**

```powershell
flutter analyze
```

Expected: No issues found

- [ ] **Step 6: 提交**

```bash
git add lib/features/chat/application/chat_sessions_controller_streaming.dart lib/features/chat/application/chat_sessions_controller.dart
git commit -m "feat: 异常 finish_reason 触发自动重试"
```

---

### Task 4: 测试 — 异常 finish_reason 重试的集成测试

**Files:**
- Modify: `test/features/settings/auto_retry_settings_controller_test.dart`
- Modify: `test/features/chat/application/chat_sessions_controller_test.dart`

**Interfaces:**
- Consumes: `retryOnAbnormalFinishReason` 字段 (from Task 1)；`FakeChatCompletionClient.enqueueDeltas` (existing)；`ChatCompletionChunk(finishReason: ...)` (existing)

- [ ] **Step 1: 在 controller 测试中补全 retryOnAbnormalFinishReason 相关断言**

在 `test/features/settings/auto_retry_settings_controller_test.dart` 中：

1. `'returns default values when no stored settings'` 测试新增断言：

```dart
expect(settings.retryOnAbnormalFinishReason, isFalse);
```

2. `'loads stored settings from SharedPreferences'` 测试的 mock JSON 新增字段：

```dart
'{"maxJitterSeconds": 30, "maxRetryCount": 5, "retryMode": "fixedInterval", "retryOnAbnormalFinishReason": true}'
```

新增断言：

```dart
expect(settings.retryOnAbnormalFinishReason, isTrue);
```

3. `'save round-trips correctly'` 测试的 save 调用新增参数：

```dart
await notifier.save(const AutoRetrySettings(
  maxJitterSeconds: 10,
  maxRetryCount: 3,
  retryMode: RetryMode.fixedInterval,
  retryOnAbnormalFinishReason: true,
));
```

新增断言：

```dart
expect(settings.retryOnAbnormalFinishReason, isTrue);
expect(storedJson, contains('"retryOnAbnormalFinishReason":true'));
```

4. 新增旧数据兼容性测试：

```dart
test('loads old JSON without retryOnAbnormalFinishReason defaults to false',
    () async {
  SharedPreferences.setMockInitialValues({
    'settings.auto_retry':
        '{"maxJitterSeconds": 20, "maxRetryCount": 2}',
  });
  final preferences = await SharedPreferences.getInstance();
  final container = await createContainer(preferences);

  final settings = container.read(autoRetrySettingsProvider);
  expect(settings.retryOnAbnormalFinishReason, isFalse);

  container.dispose();
});
```

- [ ] **Step 2: 在 chat sessions controller 测试中新增异常 finish_reason 重试测试**

在 `test/features/chat/application/chat_sessions_controller_test.dart` 的自动重试 group 中新增：

```dart
test('retryOnAbnormalFinishReason=true 时异常 finish_reason 触发重试', () async {
  container
      .read(chatSessionsProvider.notifier)
      .updateActiveConversationPreferences(autoRetryEnabled: true);

  // 保存带 retryOnAbnormalFinishReason=true 的设置
  await container.read(autoRetrySettingsProvider.notifier).save(
        const AutoRetrySettings(
          maxJitterSeconds: 0,
          maxRetryCount: 0,
          retryOnAbnormalFinishReason: true,
        ),
      );

  // 第一次返回 length（异常），第二次返回 stop（正常）
  fakeClient.enqueueDeltas([
    const ChatCompletionChunk(contentDelta: '部分内容', finishReason: 'length'),
  ]);
  fakeClient.enqueueChunks(['重试成功']);

  await sendMsg('测试异常 finish', retryDelay: Duration.zero);

  final state = container.read(chatSessionsProvider);
  expect(state.activeConversation.messages.last.content, '重试成功');
  expect(state.errorMessage, isNull);
  expect(fakeClient.requestHistory.length, 2);
});

test('retryOnAbnormalFinishReason=false 时异常 finish_reason 不触发重试', () async {
  container
      .read(chatSessionsProvider.notifier)
      .updateActiveConversationPreferences(autoRetryEnabled: true);

  // retryOnAbnormalFinishReason 保持默认 false
  fakeClient.enqueueDeltas([
    const ChatCompletionChunk(contentDelta: '部分内容', finishReason: 'length'),
  ]);

  await sendMsg('测试不重试');

  final state = container.read(chatSessionsProvider);
  // 不重试，保留异常 finish_reason 的回复
  expect(state.activeConversation.messages.last.content, '部分内容');
  expect(fakeClient.requestHistory.length, 1);
});

test('stop 和 tool_calls 不触发异常 finish_reason 重试', () async {
  container
      .read(chatSessionsProvider.notifier)
      .updateActiveConversationPreferences(autoRetryEnabled: true);

  await container.read(autoRetrySettingsProvider.notifier).save(
        const AutoRetrySettings(
          maxJitterSeconds: 0,
          maxRetryCount: 0,
          retryOnAbnormalFinishReason: true,
        ),
      );

  // stop — 正常完成，不重试
  fakeClient.enqueueDeltas([
    const ChatCompletionChunk(contentDelta: '正常回复', finishReason: 'stop'),
  ]);

  await sendMsg('测试 stop');

  final state = container.read(chatSessionsProvider);
  expect(state.activeConversation.messages.last.content, '正常回复');
  expect(fakeClient.requestHistory.length, 1);
});
```

- [ ] **Step 3: 运行全量测试**

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

Expected: EXIT=0

- [ ] **Step 4: 提交**

```bash
git add test/features/settings/auto_retry_settings_controller_test.dart test/features/chat/application/chat_sessions_controller_test.dart
git commit -m "test: 异常 finish_reason 重试的单元测试和集成测试"
```

---

### Task 5: 全量验证 + 收尾

**Files:**
- 全量分析 + 测试

- [ ] **Step 1: 运行 flutter analyze**

```powershell
flutter analyze
```

Expected: No issues found

- [ ] **Step 2: 运行全量测试**

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

Expected: EXIT=0

- [ ] **Step 3: 检查导出/导入兼容性**

确认 `settings_export_data.dart` 中 `autoRetrySettings` 字段通过 `AutoRetrySettings.toJson()` / `fromJson()` 序列化，新增字段自动被包含，无需额外改动。

- [ ] **Step 4: 最终提交（如有遗漏修复）**

仅在有额外改动时提交。

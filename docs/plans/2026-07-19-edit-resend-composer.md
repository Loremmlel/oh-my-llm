# 编辑重发回填输入区 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将聊天页面的编辑消息功能从弹窗模式改为回填输入区模式，自动恢复模板提示词和变量值。

**Architecture:** 在 `ChatMessage` 模型上新增 `templatePromptId` 和 `templateVariableValues` 字段并持久化到 SQLite。在 `_ChatScreenState` 上新增编辑状态管理，点击编辑时将消息内容回填到输入区，发送时走 `editMessage` 而非 `sendMessage`。删除旧的 `EditMessageDialog`。

**Tech Stack:** Flutter, Riverpod, SQLite (sqlite3 package)

## Global Constraints

- 注释使用简体中文
- 禁止 `part` / `part of`
- `user_version` 当前为 11，新 migration 为 V12
- 测试运行命令：`flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log`
- 使用 Bash 语法执行 git commit（不用 PowerShell here-string）

---

### Task 1: ChatMessage 模型新增模板元数据字段

**Files:**
- Modify: `lib/features/chat/domain/models/chat_message.dart`
- Test: `test/features/chat/domain/models/chat_message_test.dart` (新建)

**Interfaces:**
- Produces: `ChatMessage.templatePromptId` (`String?`, 默认 `null`), `ChatMessage.templateVariableValues` (`Map<String, String>`, 默认 `const {}`)

- [ ] **Step 1: 写 ChatMessage 新字段的失败测试**

```dart
// test/features/chat/domain/models/chat_message_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

void main() {
  group('ChatMessage 模板元数据字段', () {
    test('默认 templatePromptId 为 null', () {
      final message = ChatMessage(
        id: 'test',
        role: ChatMessageRole.user,
        content: 'hello',
        createdAt: DateTime(2026),
      );
      expect(message.templatePromptId, isNull);
    });

    test('默认 templateVariableValues 为空 map', () {
      final message = ChatMessage(
        id: 'test',
        role: ChatMessageRole.user,
        content: 'hello',
        createdAt: DateTime(2026),
      );
      expect(message.templateVariableValues, isEmpty);
    });

    test('fromJson 反序列化 templatePromptId 和 templateVariableValues', () {
      final json = {
        'id': 'test',
        'role': 'user',
        'content': 'hello',
        'createdAt': '2026-01-01T00:00:00.000',
        'parentId': null,
        'reasoningContent': '',
        'assistantModelDisplayName': '',
        'appliedCheckpointTitle': '',
        'userMessageSegments': [],
        'templatePromptId': 'tpl-1',
        'templateVariableValues': {'key': 'value'},
      };
      final message = ChatMessage.fromJson(json);
      expect(message.templatePromptId, 'tpl-1');
      expect(message.templateVariableValues, {'key': 'value'});
    });

    test('fromJson 缺失新字段时回退默认值', () {
      final json = {
        'id': 'test',
        'role': 'user',
        'content': 'hello',
        'createdAt': '2026-01-01T00:00:00.000',
        'userMessageSegments': [],
      };
      final message = ChatMessage.fromJson(json);
      expect(message.templatePromptId, isNull);
      expect(message.templateVariableValues, isEmpty);
    });

    test('toJson 包含新字段', () {
      final message = ChatMessage(
        id: 'test',
        role: ChatMessageRole.user,
        content: 'hello',
        createdAt: DateTime(2026),
        templatePromptId: 'tpl-1',
        templateVariableValues: {'lang': 'Dart'},
      );
      final json = message.toJson();
      expect(json['templatePromptId'], 'tpl-1');
      expect(json['templateVariableValues'], {'lang': 'Dart'});
    });

    test('copyWith 支持新字段', () {
      final original = ChatMessage(
        id: 'test',
        role: ChatMessageRole.user,
        content: 'hello',
        createdAt: DateTime(2026),
      );
      final copied = original.copyWith(
        templatePromptId: 'tpl-2',
        templateVariableValues: {'x': 'y'},
      );
      expect(copied.templatePromptId, 'tpl-2');
      expect(copied.templateVariableValues, {'x': 'y'});
      // 其他字段不变
      expect(copied.id, 'test');
      expect(copied.content, 'hello');
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```powershell
flutter test --reporter compact test/features/chat/domain/models/chat_message_test.dart 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 30 fltest.log
```

Expected: FAIL — `templatePromptId` getter 不存在

- [ ] **Step 3: 在 ChatMessage 中新增字段**

在 `chat_message.dart` 的 `ChatMessage` 类中：

1. 构造函数新增参数（在 `userMessageSegments` 之后）：
```dart
this.templatePromptId,
this.templateVariableValues = const {},
```

2. 新增字段声明（在 `userMessageSegments` 之后）：
```dart
final String? templatePromptId;
final Map<String, String> templateVariableValues;
```

3. `copyWith` 新增参数和赋值：
```dart
String? templatePromptId,
Map<String, String>? templateVariableValues,
// ...
templatePromptId: templatePromptId ?? this.templatePromptId,
templateVariableValues: templateVariableValues ?? this.templateVariableValues,
```

4. `toJson` 新增键：
```dart
'templatePromptId': templatePromptId,
'templateVariableValues': templateVariableValues,
```

5. `fromJson` 读取新字段（缺失时回退）：
```dart
templatePromptId: json['templatePromptId'] as String?,
templateVariableValues: (json['templateVariableValues'] as Map<String, dynamic>?)?.map(
  (k, v) => MapEntry(k, v as String),
) ?? const {},
```

6. `props` 新增：
```dart
templatePromptId,
templateVariableValues,
```

- [ ] **Step 4: 运行测试确认通过**

```powershell
flutter test --reporter compact test/features/chat/domain/models/chat_message_test.dart 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 30 fltest.log
```

Expected: EXIT=0, 全部通过

- [ ] **Step 5: 运行全量测试确认无回归**

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

Expected: EXIT=0

- [ ] **Step 6: 提交**

```bash
git add lib/features/chat/domain/models/chat_message.dart test/features/chat/domain/models/chat_message_test.dart
git commit -m "feat: ChatMessage 新增 templatePromptId 和 templateVariableValues 字段"
```

---

### Task 2: SQLite migration V12 — messages 表新增两列

**Files:**
- Modify: `lib/core/persistence/app_database.dart`

**Interfaces:**
- Consumes: Task 1 的 `ChatMessage` 新字段
- Produces: 数据库 `messages` 表包含 `template_prompt_id` 和 `template_variable_values_json` 列

- [ ] **Step 1: 在 `_createSchema` 中新增两列**

在 `app_database.dart` 的 `_createSchema` 方法中，`CREATE TABLE IF NOT EXISTS messages` 语句里 `applied_checkpoint_title` 行之后新增：

```sql
template_prompt_id TEXT DEFAULT NULL,
template_variable_values_json TEXT NOT NULL DEFAULT '{}',
```

- [ ] **Step 2: 添加 `_migrateV12` 方法**

```dart
void _migrateV12(int fromVersion) {
  if (fromVersion == 0) {
    // 全新安装，_createSchema 已包含新列
  } else {
    _connection.execute(
      'ALTER TABLE messages ADD COLUMN template_prompt_id TEXT DEFAULT NULL;',
    );
    _connection.execute(
      'ALTER TABLE messages ADD COLUMN template_variable_values_json TEXT NOT NULL DEFAULT \'{}\';',
    );
  }
  _connection.execute('PRAGMA user_version = 12;');
}
```

- [ ] **Step 3: 在 `_migrate` 中添加 V12 检查**

在 `_migrate` 方法中，V11 检查之后新增：

```dart
if (currentVersion < 12) {
  _migrateV12(currentVersion);
}
```

- [ ] **Step 4: 运行全量测试确认 migration 无回归**

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

Expected: EXIT=0

- [ ] **Step 5: 提交**

```bash
git add lib/core/persistence/app_database.dart
git commit -m "feat: SQLite migration V12 — messages 表新增模板元数据列"
```

---

### Task 3: Repository 层适配新列

**Files:**
- Modify: `lib/features/chat/data/sqlite_chat_conversation_repository.dart`

**Interfaces:**
- Consumes: Task 1 的 `ChatMessage` 新字段, Task 2 的数据库新列
- Produces: 从数据库读写 `templatePromptId` 和 `templateVariableValues`

- [ ] **Step 1: 更新 SELECT 查询**

在 `loadAllConversations` 方法的 messageRows 查询中，`SELECT` 列列表末尾新增：

```sql
template_prompt_id,
template_variable_values_json
```

- [ ] **Step 2: 更新 fromRow 映射**

在 `fromRow` 的 `ChatMessage(...)` 构造中新增：

```dart
templatePromptId: row['template_prompt_id'] as String?,
templateVariableValues: (jsonDecode(
  row['template_variable_values_json'] as String,
) as Map<String, dynamic>)
    .map((k, v) => MapEntry(k, v as String)),
```

放在 `userMessageSegments` 参数之后。

- [ ] **Step 3: 更新 INSERT 语句**

在 `replaceAll` 方法的 `messageStatement` 中：

SQL 改为：
```sql
INSERT INTO messages (
  id, conversation_id, node_index, parent_id, role,
  content, reasoning_content, assistant_model_display_name,
  applied_checkpoint_title, user_message_segments_json,
  template_prompt_id, template_variable_values_json,
  created_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  node_index = excluded.node_index,
  content = excluded.content,
  reasoning_content = excluded.reasoning_content,
  assistant_model_display_name = excluded.assistant_model_display_name,
  applied_checkpoint_title = excluded.applied_checkpoint_title,
  user_message_segments_json = excluded.user_message_segments_json,
  template_prompt_id = excluded.template_prompt_id,
  template_variable_values_json = excluded.template_variable_values_json,
  created_at = excluded.created_at
```

- [ ] **Step 4: 更新 execute 参数**

在 `messageStatement.execute([...])` 中，`jsonEncode(message.userMessageSegments...)` 之后、`message.createdAt.toIso8601String()` 之前新增：

```dart
message.templatePromptId,
jsonEncode(message.templateVariableValues),
```

- [ ] **Step 5: 运行全量测试**

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

Expected: EXIT=0

- [ ] **Step 6: 提交**

```bash
git add lib/features/chat/data/sqlite_chat_conversation_repository.dart
git commit -m "feat: Repository 层读写 messages 模板元数据列"
```

---

### Task 4: editMessage 签名变更 — 携带模板元数据

**Files:**
- Modify: `lib/features/chat/application/chat_sessions_controller.dart`
- Modify: `test/features/chat/application/chat_sessions_controller_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `ChatMessage.templatePromptId` 和 `ChatMessage.templateVariableValues`
- Produces: `editMessage` 新增可选参数 `templatePromptId` 和 `templateVariableValues`；新分支消息携带这些字段

- [ ] **Step 1: 写 editMessage 模板元数据传递的失败测试**

在 `chat_sessions_controller_test.dart` 的 `editMessage` 分组中新增：

```dart
test('editMessage 新分支消息携带模板元数据', () async {
  fakeClient.enqueueChunks(['第一次回复']);
  fakeClient.enqueueChunks(['重新生成的回复']);
  await sendMsg('原始问题');

  final userMessageId = container
      .read(chatSessionsProvider)
      .activeConversation
      .messages
      .first
      .id;

  await container.read(chatSessionsProvider.notifier).editMessage(
    messageId: userMessageId,
    nextContent: '修改后的问题',
    userMessageSegments: [
      const UserMessageSegment(
        text: '修改后的问题',
        kind: UserMessageSegmentKind.body,
      ),
    ],
    templatePromptId: 'tpl-1',
    templateVariableValues: {'lang': 'Dart'},
  );

  final messages = container
      .read(chatSessionsProvider)
      .activeConversation
      .messages;
  expect(messages[0].templatePromptId, 'tpl-1');
  expect(messages[0].templateVariableValues, {'lang': 'Dart'});
  expect(messages[0].userMessageSegments, hasLength(1));
  expect(messages[0].userMessageSegments.first.kind, UserMessageSegmentKind.body);
});

test('editMessage 默认不携带模板元数据（向后兼容）', () async {
  fakeClient.enqueueChunks(['第一次回复']);
  fakeClient.enqueueChunks(['重新生成的回复']);
  await sendMsg('原始问题');

  final userMessageId = container
      .read(chatSessionsProvider)
      .activeConversation
      .messages
      .first
      .id;

  await container
      .read(chatSessionsProvider.notifier)
      .editMessage(messageId: userMessageId, nextContent: '修改后的问题');

  final messages = container
      .read(chatSessionsProvider)
      .activeConversation
      .messages;
  expect(messages[0].templatePromptId, isNull);
  expect(messages[0].templateVariableValues, isEmpty);
  expect(messages[0].userMessageSegments, isEmpty);
});
```

- [ ] **Step 2: 运行测试确认失败**

```powershell
flutter test --reporter compact test/features/chat/application/chat_sessions_controller_test.dart 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 30 fltest.log
```

Expected: FAIL — 新参数不存在，或新分支消息字段为空

- [ ] **Step 3: 修改 editMessage 方法签名和实现**

在 `chat_sessions_controller.dart` 的 `editMessage` 方法中：

1. 新增参数：
```dart
List<UserMessageSegment> userMessageSegments = const [],
String? templatePromptId,
Map<String, String> templateVariableValues = const {},
```

2. 修改 `branchUserMessage` 构造，传入新字段：
```dart
final branchUserMessage = ChatMessage(
  id: generateEntityId(),
  role: ChatMessageRole.user,
  content: trimmedContent,
  createdAt: DateTime.now(),
  parentId: targetMessage.parentId,
  userMessageSegments: userMessageSegments,
  templatePromptId: templatePromptId,
  templateVariableValues: templateVariableValues,
);
```

- [ ] **Step 4: 运行测试确认通过**

```powershell
flutter test --reporter compact test/features/chat/application/chat_sessions_controller_test.dart 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 30 fltest.log
```

Expected: EXIT=0

- [ ] **Step 5: 运行全量测试**

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

Expected: EXIT=0

- [ ] **Step 6: 提交**

```bash
git add lib/features/chat/application/chat_sessions_controller.dart test/features/chat/application/chat_sessions_controller_test.dart
git commit -m "feat: editMessage 携带模板元数据和 userMessageSegments"
```

---

### Task 5: sendMessage 携带模板元数据

**Files:**
- Modify: `lib/features/chat/application/chat_sessions_controller.dart`
- Modify: `lib/features/chat/presentation/chat_screen.dart`
- Modify: `test/features/chat/application/chat_sessions_controller_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `ChatMessage` 新字段
- Produces: `sendMessage` 新增可选参数 `templatePromptId` 和 `templateVariableValues`；`_sendMessageContent` 传递模板元数据

- [ ] **Step 1: 修改 sendMessage 签名**

在 `chat_sessions_controller.dart` 的 `sendMessage` 方法中新增参数：

```dart
String? templatePromptId,
Map<String, String> templateVariableValues = const {},
```

在构造 `userMessage` 时传入：
```dart
templatePromptId: templatePromptId,
templateVariableValues: templateVariableValues,
```

- [ ] **Step 2: 修改 _sendMessageContent 传递模板元数据**

在 `chat_screen.dart` 的 `_sendMessageContent` 方法中：

1. 新增参数：
```dart
String? templatePromptId,
Map<String, String> templateVariableValues = const {},
```

2. 传递给 `sendMessage`：
```dart
await ref.read(chatSessionsProvider.notifier).sendMessage(
  content: trimmedContent,
  userMessageSegments: userMessageSegments,
  modelConfig: modelConfig,
  presetPrompt: presetPrompt,
  reasoningEnabled: supportsReasoning && conversation.reasoningEnabled,
  reasoningEffort: conversation.reasoningEffort,
  templatePromptId: templatePromptId,
  templateVariableValues: templateVariableValues,
);
```

- [ ] **Step 3: 修改 onSendPressed 传递模板元数据**

在 `chat_screen.dart` 的 `onSendPressed` 回调中，将 `_sendMessageContent` 调用改为传入模板信息：

```dart
await _sendMessageContent(
  content: templatedMessage.content,
  userMessageSegments: templatedMessage.userMessageSegments,
  modelConfig: selectedModel,
  presetPrompt: selectedPresetPrompt,
  conversation: conversation,
  supportsReasoning: supportsReasoning,
  isBusy: isBusy,
  templatePromptId: selectedTemplatePrompt?.id,
  templateVariableValues: _resolveTemplatePromptValues(selectedTemplatePrompt),
);
```

- [ ] **Step 4: 新增 sendMessage 模板元数据测试**

在 `chat_sessions_controller_test.dart` 的 `sendMessage` 分组中新增：

```dart
test('sendMessage 携带模板元数据', () async {
  fakeClient.enqueueChunks(['回复']);
  await container.read(chatSessionsProvider.notifier).sendMessage(
    content: '问题',
    modelConfig: testModelConfig,
    presetPrompt: null,
    reasoningEnabled: false,
    reasoningEffort: ReasoningEffort.medium,
    templatePromptId: 'tpl-1',
    templateVariableValues: {'key': 'val'},
    userMessageSegments: [
      const UserMessageSegment(text: '问题', kind: UserMessageSegmentKind.body),
    ],
  );

  final userMsg = container
      .read(chatSessionsProvider)
      .activeConversation
      .messages
      .first;
  expect(userMsg.templatePromptId, 'tpl-1');
  expect(userMsg.templateVariableValues, {'key': 'val'});
  expect(userMsg.userMessageSegments, hasLength(1));
});
```

- [ ] **Step 5: 运行全量测试**

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

Expected: EXIT=0

- [ ] **Step 6: 提交**

```bash
git add lib/features/chat/application/chat_sessions_controller.dart lib/features/chat/presentation/chat_screen.dart test/features/chat/application/chat_sessions_controller_test.dart
git commit -m "feat: sendMessage 和 onSendPressed 传递模板元数据到消息模型"
```

---

### Task 6: 编辑状态管理与输入区回填

**Files:**
- Modify: `lib/features/chat/presentation/chat_screen.dart`

**Interfaces:**
- Consumes: Task 4 的 `editMessage` 新参数, `ChatMessage.templatePromptId`, `ChatMessage.templateVariableValues`, `ChatMessage.userMessageSegments`
- Produces: `_enterEditMode`, `_cancelEditMode`, `_ComposerSnapshot`, `_editingMessageId`, 编辑模式下的发送逻辑

- [ ] **Step 1: 新增 _ComposerSnapshot 内聚类**

在 `_ChatScreenState` 类定义之前（文件顶部 import 之后），新增：

```dart
class _ComposerSnapshot {
  const _ComposerSnapshot({
    required this.bodyText,
    required this.templatePromptId,
    required this.templateVariableValues,
    required this.isComposerCollapsed,
  });

  final String bodyText;
  final String? templatePromptId;
  final Map<String, String> templateVariableValues;
  final bool isComposerCollapsed;
}
```

- [ ] **Step 2: 新增编辑状态字段**

在 `_ChatScreenState` 的字段声明区（`_restoredDraftForConversationId` 之后）新增：

```dart
String? _editingMessageId;
_ComposerSnapshot? _preEditSnapshot;
```

- [ ] **Step 3: 实现 _enterEditMode 方法**

在 `_ChatScreenState` 的方法区新增：

```dart
void _enterEditMode(ChatMessage message) {
  final templatePrompts = ref.read(templatePromptsProvider);
  final currentBody = _messageController.text;
  final currentTemplateId = ref.read(chatTemplatePromptSelectionProvider);
  final currentVariableValues = <String, String>{};
  if (currentTemplateId != null) {
    final currentTemplate = _resolveSelectedTemplatePrompt(
      templatePrompts,
      currentTemplateId,
    );
    if (currentTemplate != null) {
      currentVariableValues.addAll(
        _resolveTemplatePromptValues(currentTemplate),
      );
    }
  }

  setState(() {
    _preEditSnapshot = _ComposerSnapshot(
      bodyText: currentBody,
      templatePromptId: currentTemplateId,
      templateVariableValues: currentVariableValues,
      isComposerCollapsed: _isComposerCollapsed,
    );
    _editingMessageId = message.id;
  });

  // 恢复模板选择
  final msgTemplateId = message.templatePromptId;
  if (msgTemplateId != null) {
    final templateExists = templatePrompts.any((t) => t.id == msgTemplateId);
    if (templateExists) {
      _handleTemplatePromptSelected(msgTemplateId, templatePrompts);
      // 恢复变量值
      final template = _resolveSelectedTemplatePrompt(
        templatePrompts,
        msgTemplateId,
      );
      if (template != null) {
        for (final variable in template.inputVariables) {
          final savedValue = message.templateVariableValues[variable.name];
          final controller = _templateVariableControllers[variable.name];
          if (controller != null && savedValue != null) {
            controller.text = savedValue;
          }
        }
      }
    } else {
      _handleTemplatePromptSelected(null, templatePrompts);
    }
  } else {
    _handleTemplatePromptSelected(null, templatePrompts);
  }

  // 从 segments 提取正文
  final segments = message.userMessageSegments;
  String bodyText;
  if (segments.isNotEmpty) {
    final bodyParts = segments
        .where((s) => s.kind == UserMessageSegmentKind.body)
        .map((s) => s.text);
    bodyText = bodyParts.join();
  } else {
    bodyText = message.content;
  }
  _messageController
    ..text = bodyText
    ..selection = TextSelection.collapsed(offset: bodyText.length);

  // 保存草稿
  final conversation = ref.read(activeChatConversationProvider);
  ref.read(composerDraftProvider.notifier).setBody(conversation.id, bodyText);

  _messageFocusNode.requestFocus();
}
```

- [ ] **Step 4: 实现 _cancelEditMode 方法**

```dart
void _cancelEditMode() {
  final snapshot = _preEditSnapshot;
  if (snapshot == null) return;

  setState(() {
    _editingMessageId = null;
    _preEditSnapshot = null;
  });

  // 恢复输入区状态
  final templatePrompts = ref.read(templatePromptsProvider);
  _handleTemplatePromptSelected(snapshot.templatePromptId, templatePrompts);
  if (snapshot.templatePromptId != null) {
    final template = _resolveSelectedTemplatePrompt(
      templatePrompts,
      snapshot.templatePromptId,
    );
    if (template != null) {
      for (final variable in template.inputVariables) {
        final savedValue = snapshot.templateVariableValues[variable.name];
        final controller = _templateVariableControllers[variable.name];
        if (controller != null && savedValue != null) {
          controller.text = savedValue;
        }
      }
    }
  }

  _messageController
    ..text = snapshot.bodyText
    ..selection = TextSelection.collapsed(offset: snapshot.bodyText.length);

  final conversation = ref.read(activeChatConversationProvider);
  ref.read(composerDraftProvider.notifier).setBody(
    conversation.id,
    snapshot.bodyText,
  );

  if (_isComposerCollapsed != snapshot.isComposerCollapsed) {
    _toggleComposerCollapsed();
  }
}
```

- [ ] **Step 5: 修改 onEditMessage 回调**

在 `chat_screen.dart` 的 `onEditMessage` 回调（约第 501 行）中，将：

```dart
onEditMessage: (message) async {
  await _showEditMessageDialog(
    context,
    messageId: message.id,
    initialContent: message.content,
  );
},
```

改为：

```dart
onEditMessage: isBusy
    ? null
    : (message) {
        _enterEditMode(message);
      },
```

- [ ] **Step 6: 修改 onSendPressed — 编辑模式走 editMessage**

在 `onSendPressed` 回调中，将发送逻辑改为区分编辑/新建：

```dart
onSendPressed: selectedModel == null || isBusy
    ? null
    : () async {
        final templatedMessage = buildTemplatedUserMessage(
          body: _messageController.text,
          templatePrompt: selectedTemplatePrompt,
          variableValues: _resolveTemplatePromptValues(
            selectedTemplatePrompt,
          ),
        );
        if (templatedMessage.content.trim().isEmpty) {
          return;
        }

        _messageController.clear();
        ref
            .read(composerDraftProvider.notifier)
            .clearBody(conversation.id);

        if (_editingMessageId != null) {
          final editId = _editingMessageId!;
          setState(() {
            _editingMessageId = null;
            _preEditSnapshot = null;
          });
          await ref.read(chatSessionsProvider.notifier).editMessage(
            messageId: editId,
            nextContent: templatedMessage.content,
            userMessageSegments: templatedMessage.userMessageSegments,
            templatePromptId: selectedTemplatePrompt?.id,
            templateVariableValues: _resolveTemplatePromptValues(
              selectedTemplatePrompt,
            ),
          );
        } else {
          await _sendMessageContent(
            content: templatedMessage.content,
            userMessageSegments: templatedMessage.userMessageSegments,
            modelConfig: selectedModel,
            presetPrompt: selectedPresetPrompt,
            conversation: conversation,
            supportsReasoning: supportsReasoning,
            isBusy: isBusy,
            templatePromptId: selectedTemplatePrompt?.id,
            templateVariableValues: _resolveTemplatePromptValues(
              selectedTemplatePrompt,
            ),
          );
        }
      },
```

- [ ] **Step 7: 会话切换时清除编辑状态**

在 `ref.listen<String?>(activeConversationIdProvider, ...)` 回调中（约第 229 行），新增清除编辑状态的逻辑：

```dart
ref.listen<String?>(activeConversationIdProvider, (prev, next) {
  if (prev != next && next != null) {
    final nextConversation = ref.read(activeChatConversationProvider);
    final id = nextConversation.selectedPresetPromptId;
    setState(() {
      _selectedPresetPromptId = id == noPresetPromptSelectedId ? null : id;
      _editingMessageId = null;
      _preEditSnapshot = null;
    });
    ref.read(chatTemplatePromptSelectionProvider.notifier).clear();
  }
});
```

- [ ] **Step 8: 删除 _showEditMessageDialog 方法**

删除 `_ChatScreenState` 中的 `_showEditMessageDialog` 方法（约第 1096-1115 行）。

- [ ] **Step 9: 运行全量测试**

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

Expected: EXIT=0

- [ ] **Step 10: 提交**

```bash
git add lib/features/chat/presentation/chat_screen.dart
git commit -m "feat: 编辑消息回填输入区，替代弹窗模式"
```

---

### Task 7: ComposerData 和 ComposerCallbacks 新增编辑模式接口

**Files:**
- Modify: `lib/features/chat/presentation/widgets/composer_data.dart`

**Interfaces:**
- Produces: `ComposerData.isEditingMessage`, `ComposerCallbacks.onCancelEdit`

- [ ] **Step 1: ComposerData 新增 isEditingMessage**

在 `composer_data.dart` 的 `ComposerData` 类中：

1. 构造函数新增参数（在 `excludedMessageCount` 之后）：
```dart
required this.isEditingMessage,
```

2. 新增字段：
```dart
final bool isEditingMessage;
```

- [ ] **Step 2: ComposerCallbacks 新增 onCancelEdit**

在 `composer_data.dart` 的 `ComposerCallbacks` 类中：

1. 构造函数新增参数（在 `onSendPressed` 之前）：
```dart
this.onCancelEdit,
```

2. 新增字段：
```dart
final VoidCallback? onCancelEdit;
```

- [ ] **Step 3: 在 chat_screen.dart 传入新字段**

在 `chat_screen.dart` 构建 `ComposerData` 的地方新增 `isEditingMessage: _editingMessageId != null`。

在构建 `ComposerCallbacks` 的地方新增 `onCancelEdit: _editingMessageId != null ? _cancelEditMode : null`。

需要搜索 `chat_screen.dart` 中 `ComposerData(` 和 `ComposerCallbacks(` 的位置并添加。

- [ ] **Step 4: 运行全量测试**

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

Expected: EXIT=0

- [ ] **Step 5: 提交**

```bash
git add lib/features/chat/presentation/widgets/composer_data.dart lib/features/chat/presentation/chat_screen.dart
git commit -m "feat: ComposerData/Callbacks 新增编辑模式接口"
```

---

### Task 8: ChatComposerCard 新增编辑提示条

**Files:**
- Modify: `lib/features/chat/presentation/widgets/chat_composer_card.dart`

**Interfaces:**
- Consumes: Task 7 的 `ComposerData.isEditingMessage` 和 `ComposerCallbacks.onCancelEdit`

- [ ] **Step 1: 在 ChatComposerCard.build 中添加编辑提示条**

在 `ChatComposerCard.build` 方法中，`Column.children` 列表的最前面（在 `ComposerTemplateHeader` 之前），新增编辑提示条：

```dart
if (data.isEditingMessage)
  Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.edit_rounded,
            size: 18,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '正在编辑消息…',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          Tooltip(
            message: '取消编辑',
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: callbacks.onCancelEdit,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
```

注意：此提示条仅在 `data.isComposerCollapsed == false` 时显示（因为它在 Card 内部非折叠模式的 Column 中）。

- [ ] **Step 2: 运行全量测试**

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

Expected: EXIT=0

- [ ] **Step 3: 提交**

```bash
git add lib/features/chat/presentation/widgets/chat_composer_card.dart
git commit -m "feat: 输入区编辑提示条 UI"
```

---

### Task 9: 删除 EditMessageDialog

**Files:**
- Delete: `lib/features/chat/presentation/widgets/dialogs/edit_message_dialog.dart`

**Interfaces:**
- 无外部消费者（仅 `_showEditMessageDialog` 引用，已在 Task 6 中删除）

- [ ] **Step 1: 确认无其他引用**

搜索 `EditMessageDialog` 或 `edit_message_dialog` 的所有引用，确认已无其他消费者。

- [ ] **Step 2: 删除文件**

```powershell
Remove-Item -LiteralPath "lib\features\chat\presentation\widgets\dialogs\edit_message_dialog.dart"
```

- [ ] **Step 3: 运行全量测试**

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

Expected: EXIT=0

- [ ] **Step 4: 运行 flutter analyze**

```powershell
flutter analyze
```

Expected: No issues found

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "refactor: 删除 EditMessageDialog（已由输入区回填替代）"
```

---

### Task 10: 端到端验证与最终清理

**Files:**
- 无新增修改，仅验证

- [ ] **Step 1: 运行全量测试**

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

Expected: EXIT=0

- [ ] **Step 2: 运行 flutter analyze**

```powershell
flutter analyze
```

Expected: No issues found

- [ ] **Step 3: 搜索残留引用**

搜索 `EditMessageDialog`、`_showEditMessageDialog`、`edit_message_dialog` 确认无残留引用。

- [ ] **Step 4: 如有残留引用则修复并提交**

```bash
git add -A
git commit -m "chore: 清理编辑弹窗残留引用"
```

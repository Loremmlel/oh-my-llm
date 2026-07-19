# 编辑重发回填输入区设计

## 概述

将聊天页面的「编辑用户消息」功能从弹窗模式改为回填输入区模式。编辑时自动恢复模板提示词选择、变量值和用户正文，使编辑体验与首次发送一致。同时在消息模型上持久化模板元数据，确保编辑时可精确还原。

## 动机

当前编辑功能使用弹窗，只操作合并后的纯文本 `content`，存在以下问题：

1. 模板提示词信息在发送后丢失（模板 ID 和变量值仅存于内存 provider）
2. 用户无法区分模板内容和自己的正文，在弹窗的小框中编辑长模板很不方便
3. `editMessage` 创建的新分支消息 `userMessageSegments` 默认为空，模板/正文着色标注丢失
4. 编辑体验与首次发送体验割裂

## 决策记录

| 问题 | 选项 | 决定 | 理由 |
|------|------|------|------|
| 模板信息持久化 | 不存 / 仅存 ID / 存 ID+变量值 | 存 ID+变量值 | 完整还原，migration 开销可接受 |
| 编辑交互 | 弹窗 / 回填输入区 | 回填输入区 | 与首次发送体验一致 |
| 原消息处理 | 立即删除 / 保留可取消 | 保留可取消 | 安全，防误触 |
| 编辑状态指示 | 无 / 颜色变化 / 提示条+关闭 | 提示条+关闭 | 明确且可操作 |
| 旧消息兼容 | 仍用弹窗 / 统一回填 | 统一回填 | 体验一致 |
| 状态管理位置 | 独立 provider / 扩展草稿控制器 / 本地状态 | 本地状态 | 最简单，风险最低 |

## 数据模型变更

### ChatMessage 新增字段

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `templatePromptId` | `String?` | `null` | 发送时使用的模板提示词 ID |
| `templateVariableValues` | `Map<String, String>` | `{}` | 模板变量填充值，key=变量名 |

### SQLite migration

`messages` 表新增两列：

```sql
ALTER TABLE messages ADD COLUMN template_prompt_id TEXT DEFAULT NULL;
ALTER TABLE messages ADD COLUMN template_variable_values_json TEXT DEFAULT '{}';
```

`user_version` 递增 1。

### 序列化/反序列化

- `toJson()`: 新增 `templatePromptId` 和 `templateVariableValues` 键
- `fromJson()`: 读取新字段，缺失时回退默认值（`null` / `{}`）
- `fromRow()`: 从数据库行读取新列
- `toRow()`: 写入新列到 `messageStatement`
- `copyWith()`: 新增两个可选参数
- `props`: 新增两个字段参与相等比较

## 编辑状态管理

### 新增状态字段（`_ChatScreenState`）

```dart
/// 正在编辑的用户消息 ID；null 表示正常输入模式。
String? _editingMessageId;

/// 编辑前的输入区快照，取消编辑时恢复用。
_ComposerSnapshot? _preEditSnapshot;
```

### `_ComposerSnapshot` 内聚类

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

### 交互流程

#### 进入编辑模式：`_enterEditMode(ChatMessage message)`

1. 保存当前输入区快照到 `_preEditSnapshot`
2. 从消息恢复模板：
   - `templatePromptId` 非空且模板仍存在 → 调用 `_handleTemplatePromptSelected` 选中模板
   - 模板不存在 → 不选模板
   - `templatePromptId` 为空 → 不选模板
3. 从 `templateVariableValues` 恢复变量值到 `_templateVariableControllers`
4. 从 `userMessageSegments` 提取所有 `kind == body` 的片段拼接为正文
   - 无 segments 时正文 = `message.content`
5. 设置 `_editingMessageId = message.id`
6. 聚焦输入框
7. 同步草稿到 `ComposerDraftController`

#### 编辑中发送

`onSendPressed` 检测 `_editingMessageId != null` 时：

1. 走 `buildTemplatedUserMessage` 组装（与正常发送一致）
2. 调用 `editMessage` 并传入完整模板元数据：

```dart
await ref.read(chatSessionsProvider.notifier).editMessage(
  messageId: _editingMessageId!,
  nextContent: templatedMessage.content,
  userMessageSegments: templatedMessage.userMessageSegments,
  templatePromptId: selectedTemplatePrompt?.id,
  templateVariableValues: _resolveTemplatePromptValues(selectedTemplatePrompt),
);
```

3. 清除编辑状态：`_editingMessageId = null`，`_preEditSnapshot = null`
4. 清空输入区（同正常发送后行为）

#### 取消编辑

- 点击提示条 ✕ 按钮 → `_cancelEditMode()`
- 从 `_preEditSnapshot` 恢复输入区状态
- `_editingMessageId = null`，`_preEditSnapshot = null`

## editMessage 签名变更

```dart
Future<void> editMessage({
  required String messageId,
  required String nextContent,
  List<UserMessageSegment> userMessageSegments = const [],
  String? templatePromptId,
  Map<String, String> templateVariableValues = const {},
})
```

新分支消息携带 `templatePromptId` 和 `templateVariableValues`，下次编辑可再次还原。

## UI 变更

### 编辑提示条

在 `ChatComposerCard` 顶部（模板下拉框上方），当处于编辑模式时显示：

```
┌──────────────────────────────────────────────────┐
│ ✏️ 正在编辑消息…                              ✕ │
└──────────────────────────────────────────────────┘
```

- 左侧：编辑图标 + "正在编辑消息…"
- 右侧：✕ 关闭按钮
- 颜色：`theme.colorScheme.secondaryContainer`
- 通过 `ComposerData.isEditingMessage` 和 `ComposerCallbacks.onCancelEdit` 下传

### ComposerData 新增

```dart
final bool isEditingMessage;
```

### ComposerCallbacks 新增

```dart
final VoidCallback? onCancelEdit;
```

### EditMessageDialog

**删除** `edit_message_dialog.dart` 文件。编辑消息不再使用弹窗。

### 消息气泡编辑按钮

无变更，仍显示在用户消息上。但 `onEditPressed` 回调从 `_showEditMessageDialog` 改为 `_enterEditMode`。

## 边缘场景

| 场景 | 处理 |
|------|------|
| 模板被删除后编辑旧消息 | `templatePromptId` 指向不存在的模板 → 回退为无模板模式，正文 = 完整 `content` |
| 模板变量定义变更后编辑 | 只填充仍存在的变量，新增变量用默认值 |
| 编辑中切换会话 | 切换会话时清除编辑状态，恢复为正常模式 |
| 并发编辑两条消息 | 不可能，`_editingMessageId` 只有一个。点第二条编辑时自动取消第一条 |
| 无 segments 的旧消息 | 正文 = `message.content`，模板不选 |
| 正在流式生成时点编辑 | 编辑按钮在 `isBusy` 时已隐藏，无此场景 |
| 编辑中模板被删除 | 不影响，编辑状态已快照在本地；发送时 `templatePromptId` 指向的模板若不存在，仍用已有 segments 和 content 发送 |

## 影响范围

### 需修改的文件

| 文件 | 变更 |
|------|------|
| `chat_message.dart` | 新增 `templatePromptId`、`templateVariableValues` 字段，更新 `toJson`/`fromJson`/`copyWith`/`props` |
| `app_database.dart` | migration 新增两列 |
| `sqlite_chat_conversation_repository.dart` | `fromRow`/`toRow` 适配新列 |
| `chat_screen.dart` | 新增编辑状态字段、`_enterEditMode`、`_cancelEditMode`、修改 `onEditMessage`、修改 `onSendPressed`、新增 `_ComposerSnapshot` |
| `chat_sessions_controller.dart` | `editMessage` 签名变更，新分支消息携带模板元数据 |
| `chat_composer_card.dart` | 新增编辑提示条 |
| `composer_data.dart` | `ComposerData` 新增 `isEditingMessage`，`ComposerCallbacks` 新增 `onCancelEdit` |

### 需删除的文件

| 文件 | 理由 |
|------|------|
| `edit_message_dialog.dart` | 编辑功能改为回填输入区 |

### 不受影响

- 消息气泡渲染（`chat_message_bubble.dart`）
- SSE 解析、网络层
- 模板提示词管理页
- 会话列表页

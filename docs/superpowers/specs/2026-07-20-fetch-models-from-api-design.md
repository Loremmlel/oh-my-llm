# 从 API 拉取模型列表功能设计

## 概述

在服务商下新增模型时，支持从服务器的 `/models` 端点拉取可用模型列表，用户勾选并填写显示名后批量添加。保留原有的手动输入模式，通过弹窗顶部切换。

## 动机

当前添加模型完全手动，用户需要逐个输入模型 ID。存在两个痛点：

1. 麻烦：服务商可能有几十个模型，逐个手输 modelName 效率极低。
2. 不知道 ID：有些服务商不直接在文档里暴露所有模型 ID，需要通过 API 查询才能获取。

OpenAI 兼容 API 提供了标准的 `GET /v1/models` 接口，返回可用模型列表。利用这个接口可以一次性展示所有模型，让用户批量选择添加。

## 决策记录

| 问题 | 选项 | 决定 | 理由 |
|------|------|------|------|
| 拉取入口位置 | 模型表单内切换 / 服务商表单内 / 两处都支持 | 模型表单内切换 | 入口统一在"新增模型"，手动模式不受影响，交互最自然 |
| models URL 确定 | 自动推导 / 推导+可覆盖 / 用户手填 | 推导+可覆盖 | 默认推导零配置，特殊厂商可纠正 |
| 已存在模型处理 | 默认不选可重复 / 隐藏 / 置灰不可选 | 默认不选可重复 | 用户可见全貌，保留选择自由度 |
| 显示名默认值 | 模型 ID / 从 owned_by 推导 / 留空强制填 | 模型 ID | 最简单，用户自行决定是否修改 |
| 厂商差异处理 | 只 OpenAI 标准 / 每厂商适配器 | 只 OpenAI 标准 | 覆盖绝大多数场景，失败回退手动，YAGNI |
| 确认按钮约束 | 全部填完才能确认 / 可部分填空着用 ID 兜底 | 全部填完才能确认 | 符合主人原始需求，防止误操作 |
| 方案选择 | 单弹窗分页切换 / 两个独立弹窗 / 拉取作为辅助回填 | 单弹窗分页切换 | 贴合"一个按钮即可手动也可请求"的需求，支持批量 |

## OpenAI 标准 /models 接口

### 端点

```
GET /v1/models
```

### 请求头

```
Authorization: Bearer {apiKey}
Accept: application/json
```

### 响应格式

```json
{
  "object": "list",
  "data": [
    {
      "id": "gpt-4o",
      "object": "model",
      "created": 1715367049,
      "owned_by": "openai"
    }
  ]
}
```

### Model 对象字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `string` | 模型标识符，API 调用时使用 |
| `object` | `"model"` | 固定值 |
| `created` | `integer` | Unix 时间戳（秒） |
| `owned_by` | `string` | 拥有者组织 |

**注意**：标准接口不返回模型 icon。个别厂商（如 OpenRouter）可能扩展额外字段，但本设计不依赖 icon，只使用 `id` 字段。`owned_by` 保留用于未来可能的显示名推导，当前不使用。

## 架构

### 新增文件

| 文件 | 职责 |
|------|------|
| `lib/features/settings/data/model_list_client.dart` | GET /models 的 HTTP 客户端，返回解析后的模型列表 |
| `lib/features/settings/data/model_list_url.dart` | 纯函数：从 chat completions URL 推导 models URL |
| `lib/features/settings/presentation/widgets/form/model_fetch_section.dart` | 拉取模式的 UI 区块（URL 展示 + 拉取按钮 + 模型列表 + 勾选） |

### 修改文件

| 文件 | 改动 |
|------|------|
| `model_config_form_dialog.dart` | 顶部加 `SegmentedButton` 切换"手动"/"拉取"；编辑模式（`initialValue != null`）只显示手动表单，不显示切换 |
| `llm_model_configs_controller.dart` | 新增 `upsertModels()` 批量添加方法 |

### 不动的文件

- `LlmProviderConfig` / `LlmProviderModelConfig` 数据模型完全不变
- `provider_tile.dart` 入口完全不变（仍然点"新增模型"打开弹窗）
- `SettingsFormDialogScaffold` / `SettingsFormDialogStateMixin` 复用

### 设计决策

- **ModelListClient 放 settings 域**：这是设置功能，不是 chat 功能。复用全局 `httpClientProvider` 和 `appNetworkLoggerProvider`，不依赖 `OpenAiCompatibleChatClient`。
- **批量添加**：controller 新增 `upsertModels(providerId, List<LlmProviderModelConfig>)`，避免循环调用 `upsertModel` 导致多次 setState 和持久化。

## models URL 推导

### 推导规则

纯函数 `deriveModelsUrl(String chatCompletionsUrl) -> String`：

1. 解析输入 URL
2. 去掉末尾斜杠
3. 如果路径以 `/chat/completions` 结尾 -> 替换为 `/models`
   - `https://api.deepseek.com/v1/chat/completions` -> `https://api.deepseek.com/v1/models`
   - `https://api.openai.com/v1/chat/completions` -> `https://api.openai.com/v1/models`
4. 如果路径以 `/chat/completions/` 结尾（带尾斜杠）-> 同上
5. **兜底**：如果路径不以 `/chat/completions` 结尾（用户可能只填了 base URL），在末尾追加 `/models`
   - `https://some.api.com/v1` -> `https://some.api.com/v1/models`
   - `https://some.api.com/v1/` -> `https://some.api.com/v1/models`

### 覆盖交互

拉取区块顶部有一个折叠的"高级"区域：

- 默认收起，显示推导出的 URL（灰色小字只读）
- 展开后是一个 `TextFormField`，允许用户编辑 URL
- 用户编辑后，以编辑后的 URL 为准请求

## UI 交互流程

### 弹窗结构

```
┌─────────────────────────────────────┐
│  新增模型                            │
├─────────────────────────────────────┤
│  [手动输入] [从 API 拉取]  <- SegmentedButton
├─────────────────────────────────────┤
│  （根据模式显示不同内容）              │
│                                      │
│  手动模式：现有表单（显示名/模型名/推理开关）
│  拉取模式：见下节                     │
├─────────────────────────────────────┤
│           [取消]  [保存/添加所选模型]   │
└─────────────────────────────────────┘
```

### 编辑模式特例

当 `initialValue != null`（编辑现有模型）时：**不显示模式切换**，只展示手动表单。因为编辑单个模型时拉取列表没有意义。

### 拉取模式状态机

```
[空闲] --点击拉取--> [加载中] --成功--> [已加载：展示列表]
                     |
                     --失败--> [错误：显示错误信息 + 重试按钮]
```

### 拉取区块布局（自上而下）

1. **折叠的"高级"区域**：默认收起，展示推导 URL（灰色小字）。展开后可编辑 URL。
2. **「拉取模型」按钮**：点击发起请求。加载中显示 spinner + 禁用。
3. **状态区域**：
   - 空闲：提示文字「点击上方按钮从服务器拉取可用模型列表」
   - 加载中：`CircularProgressIndicator` + 「正在拉取...」
   - 错误：红色错误文字 + 「重试」按钮（错误信息含 HTTP 状态码和响应体摘要）
   - 已加载：模型列表

### 模型列表行布局

每行：

```
[Checkbox] model-id-text          [已存在标识(灰色chip)]
            [TextFormField: 显示名称]
```

- **Checkbox**：勾选状态。已存在的模型默认不勾选。
- **model id**：只读文本，服务器返回的 id。
- **已存在标识**：如果该 model id 已在当前服务商下存在，显示灰色小 chip「已存在」。
- **显示名输入框**：勾选后启用，默认填入 model id。未勾选时禁用。

### 确认按钮约束

- 切到拉取模式后，底部按钮文字变为「添加所选模型」。
- **启用条件**：至少勾选一个模型，且所有勾选的模型显示名非空。
- **未拉取时**：按钮禁用，文字灰色。
- 点击后调用 `upsertModels()` 批量添加，然后关闭弹窗。

### 提交后反馈

弹窗关闭后，由调用方（`settings_screen.dart` 中打开弹窗的地方）调用 `showSettingsSnackbar` 提示「已添加 N 个模型」。弹窗本身不显示 snackbar。

## 数据流与持久化

### RemoteModelInfo 传输对象

```dart
class RemoteModelInfo {
  const RemoteModelInfo({required this.id, this.ownedBy});
  final String id;
  final String? ownedBy;
}
```

纯传输对象，不持久化。只提取 `id`，忽略 `created`、`object` 等字段。

### 提交流程

**手动模式**（不变）：表单校验 -> `upsertModel(providerId, model)` -> 关闭弹窗。

**拉取模式**：

1. 收集所有勾选的模型 -> 构造 `List<LlmProviderModelConfig>`
2. 每个模型用 `generateEntityId()` 生成 id
3. `displayName` 取输入框值（trim 后非空）
4. `modelName` 取服务器返回的 model id
5. `supportsReasoning` 默认 `false`（拉取流程不设置此项，用户后续可在编辑模型时开启）
6. 调用 `upsertModels(providerId, List<LlmProviderModelConfig>)` 批量添加
7. 关闭弹窗
8. 调用方显示 snackbar 提示「已添加 N 个模型」（跳过重复项时 N 为实际新增数）

### Controller 新增方法

```dart
/// 在指定服务商下批量新增模型，跳过已存在同 modelName 的模型。
Future<void> upsertModels({
  required String providerId,
  required List<LlmProviderModelConfig> models,
}) async {
  // 一次 setState + 一次 saveProviders
  // 对每个 model 检查是否已存在同 modelName，存在则跳过
}
```

**去重逻辑**：按 `modelName` 去重（与 `mergeImportedProviders` 一致）。即使 UI 允许用户勾选已存在的模型，持久化层也会跳过重复项，保证数据一致性。

### ModelListClient 请求构建

```dart
Future<List<RemoteModelInfo>> fetchModels({
  required String modelsUrl,
  required String apiKey,
}) async {
  final uri = Uri.parse(modelsUrl);
  final request = http.Request('GET', uri)
    ..headers.addAll({
      'Authorization': 'Bearer $apiKey',
      'Accept': 'application/json',
    });
  // 复用 httpClientProvider + customHeaders + networkLogger
  // 解析 {object: "list", data: [{id, ...}]} 格式
}
```

## 错误处理与边界情况

### 错误处理

| 场景 | 处理 |
|------|------|
| URL 解析失败 | 弹窗内显示错误，不发起请求 |
| 网络超时 / 连接失败 | 显示错误信息 + 重试按钮 |
| HTTP 非 200 | 显示状态码 + 响应体前 200 字摘要 + 重试按钮 |
| 响应 JSON 解析失败 | 显示「响应解析失败」+ 原始响应前 200 字 + 重试按钮 |
| 返回空列表 | 显示「服务器未返回任何模型」+ 重试按钮 |
| `data` 字段缺失或格式不符 | 同 JSON 解析失败 |

**原则**：错误以 inline 方式显示在拉取区块内（错误文字 + 重试按钮），不用 SnackBar/Dialog。符合项目核心域规则「错误以 inline 呈现，不用 SnackBar/Dialog」的精神，避免弹窗套弹窗。

### 边界情况

| 场景 | 处理 |
|------|------|
| 用户切走再切回拉取模式 | 保留已拉取的列表和勾选状态（State 保存在 widget 中） |
| 用户编辑 URL 后重新拉取 | 用编辑后的 URL 请求 |
| 推导 URL 为空（provider.apiUrl 为空） | 拉取按钮禁用，提示「请先在服务商配置中填写 API URL」 |
| apiKey 为空 | 仍然发请求（Bearer 空字符串），让服务器返回 401 错误更明确 |
| 用户勾选模型后清空显示名 | 该行高亮红色边框，确认按钮禁用 |
| 模型 id 极长 | UI 截断显示，完整 id 在 tooltip |

## 测试策略

### 单元测试

| 测试文件 | 测什么 |
|----------|--------|
| `test/features/settings/data/model_list_url_test.dart` | `deriveModelsUrl()` 纯函数：标准 chat/completions 结尾、base URL 结尾、带尾斜杠、空字符串、非法 URL |
| `test/features/settings/data/model_list_client_test.dart` | `ModelListClient`：解析标准 `{data:[{id,...}]}`、空 data、非标准 JSON、HTTP 错误码、网络异常。用 `MockClient`（`package:http` 的 test 桩） |
| `llm_model_configs_controller_test.dart`（已有文件追加） | `upsertModels()`：批量添加、跳过重复 modelName、空列表不改动 |

### Widget 测试

| 测试文件 | 测什么 |
|----------|--------|
| `model_config_form_dialog_test.dart`（已有文件追加） | 模式切换、拉取加载状态、拉取错误显示、列表勾选、显示名校验、确认按钮启用/禁用逻辑、批量提交调用 `upsertModels` |

### 测试反模式规避

- 不测 `SegmentedButton` 内部实现，只测"手动表单"和"拉取区块"是否可见
- 不测像素位置，测逻辑 finder
- Fake client 只覆盖 `fetchModels()`，不引入真实 HTTP

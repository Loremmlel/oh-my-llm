# Chat 行为与生命周期

适用于 Chat，以及修改对话历史、Prompt 或文本生成适配的任务。先读根与 [lib/AGENTS.md](../../AGENTS.md)；协议任务同时读 [LLM](../../core/llm/AGENTS.md) / [HTTP](../../core/http/AGENTS.md)，写入与迁移读 [持久化规则](../../core/persistence/AGENTS.md)。

## Generation 与工作区

- `ChatGenerationCoordinator` / `ChatGenerationRun` 独占 prepare、stream、stop、cancel、retry、finalize 和持久化终态，经显式 `ChatGenerationPhase` / `ChatGenerationOutcome` 转移。`ChatSessionsState` 兼容字段只是生命周期快照投影，不另建 flag 状态机。
- 工作区传递不可变 `ChatWorkspaceComposerState` / `ChatWorkspaceMessagesState` / `ChatWorkspaceBindings`；消息区独立 Consumer 监听高频状态，bindings 只在 build 组合，不持久化 UI controller。
- 草稿归 `ComposerDraftController`，编辑事务、焦点、滚动归 `ChatScreen` 本地；切换会话不得泄漏模板变量或编辑快照。
- 每个协议 chunk 写入独立 `ChatStreamingReply`，不直接写会话列表。`StreamMarkdown` 合并 Markdown 刷新，侧栏、composer、收藏查询和滚动导航元数据不随 chunk 重建。
- `isStreaming` 仅内存 UI 状态，不持久化；`finishReason` 持久化。异常 finish_reason（如 length）按 `_sendWithOptionalAutoRetry` 的政策重试。

## 消息树与展示

- `parentId ?? rootConversationParentId`（`'__root__'`）是有效父节点。`selectedChildByParentId` 记录选中子节点，从 root 沿选择链解析可见路径，无选择取同级第一条。
- 编辑用户消息创建新节点，parentId 与原消息相同，更新选择使新节点生效；旧分支保留在 messageNodes。仅最新一条 assistant 回复可重试。
- 树操作集中在 [chat_message_tree.dart](application/sessions/chat_message_tree.dart)：resolveMessageTreeState、appendNodeToTree、replaceAssistantMessageInTree、removeNodeFromTree。
- 推理与正文在三处保持分离：ChatMessage 的 content / reasoningContent 分别 JSON 序列化；SQLite 的 `content TEXT NOT NULL` / `reasoning_content TEXT NOT NULL DEFAULT ''`；UI 的 ReasoningPanel 仅非空时独立显示。
- 聊天错误嵌入 assistant 气泡的 `ChatInlineErrorCard` / `ChatInlineEmptyReplyCard`；不使用 showSnackBar 或错误 Dialog，showDialog 仅用于删除、重命名、序列选择等确认操作。
- 未手动命名时标题取首条用户消息的 `normalizedContent.characters.take(15)`；`hasCustomTitle` 判断 title 非 null 且 trim 后非空。手动命名后历史列表不显示预览。历史搜索只匹配标题与用户消息，不匹配 assistant 回复。

## 请求准备与文本政策

[chat_request_message_builder.dart](application/requests/chat_request_message_builder.dart) 的顺序必须保持：

1. 检查点记忆（system）
2. 模板 placement == before
3. 经 request_message_filter 过滤的有效历史，不含本次最新输入
4. 模板 placement == beforeLatestInput
5. 显式指定的本次最新用户输入
6. 模板 placement == after

宏预设先按原条目列表求值，再按注入位置组装；普通预设不执行宏。上下文查看复用相同准备函数，生成中读取当前请求快照。

- `data/generation/chat_text_generation_adapter.dart` 保留空回复异常、默认选项、Messages 文本 system 转换与同角色合并；内联推理标签由 Chat 的 `inline_reasoning_tag_splitter.dart` 处理。
- `output_regex_processor.dart` 按 order 升序链式应用，缓存 RegExp 编译结果。

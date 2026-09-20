# 图片输入基础设施

## 官方协议调查

核对日期：2026-09-20。三种协议都支持在用户消息内混合文本与图片，模型本身仍需支持视觉输入。

| 协议 | 图片内容块 | 本地文件的发送方式 |
| --- | --- | --- |
| Chat Completions | `image_url`，值为含 `url` 的对象 | `url` 使用带 MIME 的 base64 data URL |
| Responses | `input_image`，文本使用 `input_text` | `image_url` 直接使用 base64 data URL |
| Anthropic Messages | `image`，含 `source` | `source.type=base64`，分别提供 `media_type` 和 `data` |

来源：[OpenAI Chat Completions API](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)、[OpenAI 图片与视觉指南](https://developers.openai.com/api/docs/guides/images-vision)、[Anthropic 视觉指南](https://platform.claude.com/docs/en/build-with-claude/vision)。

官方还提供远程 URL／部分协议的 Files API 引用。当前客户端采用三者共有的内联图片方式，不创建厂商文件、不依赖临时外链。保留已有流式输出、工具终态、取消和原生续接机制；本次只新增图片输入，未实现图片生成、音频、视频或 Agent 图片工作流。

## 请求与存储边界

- `LlmTextMessage` 保持纯文本调用格式；`LlmUserMessage` 持有有序的 `LlmTextPart`／`LlmImagePart`，协议编码器完成转换。图片字节防御复制，不可由调用方改写。
- Chat 的消息、草稿和请求使用 `ChatImageAttachment`。它只含内容哈希、显示名称、MIME、字节数与尺寸；SQLite 的 `messages.images_json` 保存这些元数据，不保存图片、base64 或绝对路径。
- 图片文件位于数据库同级 `chat_images/`，以 SHA-256 内容哈希命名。先写临时文件并完成重命名，再返回可发送的引用。发送和显示时检查大小与哈希；缺图、损坏图显式报错，不静默退回纯文本。
- v22 → v23 只新增元数据列，旧消息默认空图片列表。已发布迁移保留，最低支持版本不提高。消息树与后台 Isolate 传输携带图片引用，因此编辑和切换版本不会覆盖旧分支的图片。
- 发送时才读取当前有效上下文中的图片，消息排除和检查点裁剪仍先执行。Messages 的相邻角色合并保留每段图文顺序。图片请求关闭 SSE 原文与错误响应原文落盘，请求正文继续默认不落盘。

## 本次应用限制

这些是客户端的保守资源策略，不是对所有模型能力和官方上限的声明：

- 每条消息最多 8 张，导入文件最多 20 MiB、约 3200 万像素。
- 支持 JPEG、PNG、GIF、WebP；后台读取首帧、修正方向，将长边缩到最多 2048 像素，保存静态 JPEG／PNG。原文件保持不变。
- 保存后每张最多 4 MiB；一次请求的图片原始字节合计最多 20 MiB，为 base64 膨胀留出空间。超限提示缩小图片或排除早期图片消息。
- 草稿仍按会话保存在内存，重启后清空。已发送记录及图片文件持久化。`X` 只从当前草稿移除引用；图片可能被其它消息分支复用，因此暂不自动清理无引用文件。备份完整聊天数据时同时备份数据库和 `chat_images/`。
- 设置交换和同步携带模型的图像能力配置，但不传输聊天图片；收藏也不是图片备份方式。

## 模型能力边界

- 模型配置新增独立的 `supportsImageInput`，缺省为 false；不根据名称推测能力。它声明模型是否能接收图像，不会强制每次请求带图。后续增加音频／视频时各自声明输入能力，不以一个总开关授予所有模态。
- 单独编辑、API 批量添加、配置导入／导出和同步均保留该字段。API 拉取时每个模型可分别指定深度思考与图像能力，取消勾选后再勾选保留当前设置。
- 模型卡片提供「深度思考」「图像」两个快捷控件，立即持久化。宽卡片与名称同行，窄卡片整组放在名称下方；长名称省略并提供提示，大字号允许控件换行。保存期间禁用该模型控件，失败恢复原状态并在卡片内显示原因。
- 未开启图像能力时，点击 `+` 或粘贴图片会在输入区提示；普通文本粘贴照常。切换模型或关闭图像能力后，保留已有图文草稿，禁用含图片上下文的发送。
- 拦截检查有效历史与当前草稿，遵循消息排除、检查点覆盖和编辑分支。生成适配器在读图和网络请求前再次检查，覆盖重试、固定顺序与检查点总结等入口；总结请求保留源图片，不默默丢弃图像。

## 交互约定

`+` 在 Windows 打开图片文件选择，在 Android 打开系统相册；复用现有 `file_picker` 的 `FileType.image`。[文件选择器变更说明](https://pub.dev/packages/file_picker/changelog)

正文上方显示固定尺寸缩略图。悬停或键盘聚焦出现遮罩，点击打开 ID 路由的预览页，提供缩放、恢复、关闭、Escape 与系统返回。移除按钮始终可见。短视口内输入区可以滚动。

Ctrl+V／Command+V 优先读取剪贴板图片，没有图片时插入文本；只在正文焦点内拦截。图片读取使用 `pasteboard`，Android 本次只读取剪贴板 URI，不调用需要 FileProvider 的图片写入 API。[插件文档](https://pub.dev/packages/pasteboard)

`pasteboard` 暂固定 0.5.0：上游 Android 构建仍直接应用旧 Kotlin 插件，与本仓库 AGP 9 的 built-in Kotlin 冲突。`android/settings.gradle.kts` 将该模块的构建配置指向 `android/pasteboard/`，继续编译原包源码，不修改 Pub 缓存或全局 Kotlin 配置。这是单插件构建兼容层，由 Android Release 构建保护；上游发布支持 built-in Kotlin 的版本后升级依赖并删除这两处适配。[Flutter 插件迁移说明](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors)

选图与处理期间禁用发送，允许取消编辑和切换会话，过期的异步结果丢弃；失败提示保留在输入区并保留已有草稿。纯图片消息可发送，编辑图片可以形成新分支。

## 验证所有权

协议格式、顺序、不可变性与预算由 `llm_image_input_test.dart` 验证；文件系统与解码失败由 `file_chat_image_store_test.dart` 验证；迁移和 SQL 引用回读由 `chat_image_migration_test.dart` 及现有最低版本迁移测试验证。Chat 适配器验证 Messages 合并、缺图拒绝和三协议的能力拦截。页面测试覆盖选择、遮罩、预览、移除、图片／文本粘贴、编辑取消、异步过期结果与能力变更后的草稿保留；模型配置、快捷修改和批量添加由设置测试保护。

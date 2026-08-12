# 项目文件组织重构设计

**状态：** 已确认，等待实施计划

**日期：** 2026-08-12

## 1. 背景

项目已采用 `features/<feature>/<layer>` 的 feature-first + layered 结构，并通过
`tool/check_import_boundaries.dart` 约束 `presentation`、`application`、`domain`、
`data` 的依赖方向。当前问题不是顶层架构错误，而是部分 layer 下缺少第二级业务
切片，导致大量文件平铺在同一目录中，IDE 展开后难以浏览。

现状扫描中的主要热点如下：

| 目录 | 直接 Dart 文件 | 子目录 | IDE 可见项 |
|---|---:|---:|---:|
| `lib/features/chat/presentation/widgets` | 27 | 2 | 29 |
| `lib/features/chat/application` | 22 | 1 | 23 |
| `test/features/chat/application` | 22 | 1 | 23 |
| `lib/features/settings/application` | 18 | 0 | 18 |
| `lib/features/settings/domain/models` | 17 | 0 | 17 |
| `lib/features/media/data` | 13 | 1 | 14 |
| `lib/features/settings/presentation/widgets` | 9 | 4 | 13 |
| `test/features/media/data` | 13 | 0 | 13 |
| `test/helpers` | 13 | 0 | 13 |
| `lib/features/sync/data` | 12 | 0 | 12 |
| `lib/features/sync/domain/models` | 11 | 0 | 11 |

仓库根目录还存在 82 个由 Agent 测试、分析、构建或诊断生成的 ignored `*.log`
文件。它们不受版本控制，但会污染 IDE 根目录。

## 2. 参考原则

Flutter 官方架构指南强调职责分离、明确边界和可测试组件，同时明确这些建议需要
根据项目实际情况适配，而不是固定目录模板：

- <https://docs.flutter.dev/app-architecture/guide>
- <https://docs.flutter.dev/app-architecture/case-study>

Flutter 官方案例采用 feature 与 type 的混合组织，并让 `test/` 镜像 `lib/`。
Very Good Ventures 同样建议大型 Flutter 项目按业务域或 feature 聚合，避免随着文件
增加形成宽泛、难导航的类型目录：

- <https://verygood.ventures/blog/building-better-software-the-importance-of-rigorous-code-reviews/>

本项目已经建立了比官方案例更适合当前 Riverpod/ports 架构的四层结构，因此本次
不迁移到 MVVM 命名，也不推倒现有 feature-first 边界。重构只在既有 layer 内增加
业务切片。

## 3. 目标

1. 将当前 10–29 个可见项的热点目录收敛为可快速理解的业务切片。
2. 保留 `features/<feature>/<layer>`，确保现有 import boundary 仍能识别 layer。
3. 让 `test/` 与 `lib/` 同步迁移并尽可能镜像被测代码的位置。
4. 以完整文件移动为主，不改变类名、公开接口、状态所有权和产品行为。
5. 统一 Agent 生成日志到 ignored `logs/`，清理仓库根目录。
6. 将迁移拆成可独立验证的 feature 批次，避免一次性大爆炸式移动。

## 4. 非目标

- 不拆分任何生产大文件，包括 `chat_sessions_controller.dart`、
  `chat_screen.dart`、`sync_protocol_message.dart`。
- 不迁移到另一套架构或状态管理方案。
- 不改变任何序列化格式、SQLite schema、Settings export version 或 Sync 协议。
- 不抽取新的 application port，不消除 Settings 的存量 application→data 依赖。
- 不移动类、文件或行为到其他 feature。
- 不整理 `lib/core/persistence`、`lib/core/http`、
  `lib/features/sync/application`、`test/integration`。
- 不新增 package，不创建大量 barrel，不重命名生产类或生产文件。
- 不改变 CI 临时 runner 中用于失败产物上传的根目录 `fltest.log`。

## 5. 通用组织规则

1. 现有四层保持不变：`domain`、`data`、`application`、`presentation`。
2. layer 内优先使用业务能力名，例如 `generation`、`sessions`、`prompts`、
   `providers`、`transfer`、`http`、`udp`，不使用 `misc`、`common`、`utils` 等
   无法表达所有权的兜底目录。
3. 一般将目录控制在 4–8 个可见项；9–10 项在职责内聚时可以接受。
4. 不为单个文件机械创建目录。单文件目录只允许用于已经明确且稳定的边界，例如
   Chat workspace view state。
5. 只有当一个业务切片自身仍然过宽时，才增加第二级 `forms`、`lists`、
   `controls`、`fields`、`layout` 等局部技术分组。
6. 生产文件名保持不变。测试文件只有在当前名称错误表达被测对象时才重命名。
7. 跨 feature、跨 `core/`、跨 `app/` 的 import 继续使用
   `package:oh_my_llm/...`；同一 feature 内继续使用相对 import。
8. `test/` 跟随生产路径迁移；聚合验证多个切片的测试可以保留在共同父目录。
9. 保留现有 `widgets.dart`、`settings_widgets.dart` 稳定导出入口，不为每个新目录
   创建 barrel。
10. 源文件与对应测试必须作为同一迁移单元，不允许先移动一侧再留待后续修复。

## 6. Chat 目标结构

### 6.1 Application

```text
lib/features/chat/application/
  composer/
    chat_composer_command.dart
    composer_collapsed_controller.dart
    composer_draft_controller.dart
    templated_user_message_builder.dart
  favorites/
    chat_favorite_intent_command.dart
    chat_favorites_facade.dart
  generation/
    chat_generation_contract.dart
    chat_generation_coordinator.dart
    chat_generation_lifecycle.dart
    chat_generation_run.dart
    output_regex_processor.dart
  history/
    history_pagination_controller.dart
  requests/
    chat_request_message_builder.dart
    checkpoint_request_context.dart
    request_message_filter.dart
  sessions/
    chat_message_tree.dart
    chat_sessions_controller.dart
    chat_sessions_controller_streaming.dart
    chat_sessions_controller_support.dart
    chat_sessions_state.dart
  sidebar/
    chat_sidebar_controller.dart
  workspace/
    chat_workspace_view_state.dart
  ports/
    chat_conversation_repository.dart
    chat_generation_client.dart
```

`generation` 管理一次生成运行和生命周期，`sessions` 管理会话、消息树以及流式结果
进入会话的过程，`requests` 管理请求构建与筛选。三者不得合并成泛化的
`controllers` 或 `services`。

### 6.2 Data

```text
lib/features/chat/data/
  generation/
    protocol_routing_chat_generation_client.dart
    anthropic/
      anthropic_message_transformer.dart
      anthropic_messages_client.dart
      anthropic_parser.dart
    chat_completions/
      chat_completions_client.dart
      chat_completions_parser.dart
      inline_reasoning_tag_splitter.dart
    responses/
      responses_client.dart
      responses_parser.dart
  persistence/
    background_chat_repository.dart
    chat_sql_codec.dart
    chat_writer_entry_point.dart
    sqlite_chat_conversation_repository.dart
```

协议路由和三个协议客户端继续构成生产唯一的 generation 实现。持久化目录继续保留
后台写入、防抖和 SQLite codec 的现有职责。

### 6.3 Presentation widgets

```text
lib/features/chat/presentation/widgets/
  composer/
    chat_composer_card.dart
    composer_helpers.dart
    controls/
      auto_retry_toggle.dart
      composer_effort_pill.dart
      composer_pill_toggle.dart
      composer_send_button.dart
      thinking_toggle.dart
    fields/
      composer_message_field.dart
      composer_template_variable_fields.dart
      number_variable_field.dart
    layout/
      composer_compact_action_row.dart
      composer_desktop_settings_row.dart
      composer_provider_model_row.dart
      composer_template_header.dart
  messages/
    chat_messages_panel.dart
    empty_conversation_view.dart
    bubble/
      cached_chat_message_bubble.dart
      chat_inline_empty_reply_card.dart
      chat_inline_error_card.dart
      chat_message_bubble.dart
      reasoning_panel.dart
      streaming_markdown_view.dart
      user_message_collapse.dart
    navigation/
      message_anchor_rail.dart
      message_version_info.dart
      message_version_navigator.dart
  prompts/
    preset_prompt_message_card.dart
    preset_prompt_message_detail_dialog.dart
    preset_prompt_panel.dart
  sidebar/
    chat_activity_bar.dart
    chat_compact_panel.dart
    chat_sidebar_panel.dart
    conversation_history_panel.dart
    grouped_conversation_list.dart
  workspace/
    chat_workspace.dart
    chat_workspace_bindings.dart
  dialogs/
    add_to_favorites_dialog.dart
    checkpoint_selection_header.dart
    checkpoint_selection_tile.dart
    conversation_checkpoints_dialog.dart
    delete_message_dialog.dart
    fixed_prompt_sequence_runner_dialog.dart
    message_request_filter_dialog.dart
    stop_streaming_confirm_dialog.dart
  widgets.dart
```

`widgets.dart` 留在原位置并更新 exports。`chat_screen.dart` 继续通过该入口消费 widgets。

### 6.4 Tests

```text
test/features/chat/
  application/
    composer/
    favorites/
    generation/
    history/
    requests/
    sessions/
      chat_sessions_controller/
    sidebar/
    workspace/
    ports/
  data/
    generation/
      anthropic/
      chat_completions/
      responses/
    persistence/
  domain/
    models/
  presentation/
    chat_screen_test.dart
    chat_screen/
    widgets/
      composer/
        controls/
      messages/
        bubble/
        navigation/
```

具体规则：

- application 测试与 6.1 的目标目录一致；
  `chat_generation_client_contract_test.dart` 进入 `application/ports/`。
- `chat_sessions_controller_test.dart`、持久化测试、state/tree 测试和现有 case-files
  全部进入 `application/sessions/`。
- Chat data 测试与 6.2 的 `generation`、`persistence` 镜像。
- `chat_checkpoint_test.dart`、`chat_conversation_summary_test.dart`、
  `chat_conversation_test.dart`、`chat_message_test.dart` 进入 `domain/models/`。
- `chat_screen_test.dart` 及 `chat_screen/` case-files 从 feature 根移动到
  `presentation/`。
- 当前 `test/features/chat/widgets/` 消除，测试进入对应的
  `presentation/widgets/composer` 或 `presentation/widgets/messages` 切片。
- `chat_conversation_repository_test.dart` 重命名为
  `sqlite_chat_conversation_repository_test.dart` 并进入 `data/persistence/`。

## 7. Settings 目标结构

### 7.1 Application

```text
lib/features/settings/application/
  preferences/
    auto_retry_settings_controller.dart
    chat_defaults_controller.dart
    custom_headers_controller.dart
    font_size_settings_controller.dart
    output_processing_settings_controller.dart
    settings_tab_preferences.dart
  providers/
    llm_model_configs_controller.dart
    llm_provider_equivalence.dart
    model_catalog_workflow.dart
  prompts/
    fixed_prompt_sequences_controller.dart
    memory_prompts_controller.dart
    preset_prompts_controller.dart
    settings_entity_controller.dart
    template_prompts_controller.dart
  transfer/
    settings_import_deduplicator.dart
    settings_import_executor.dart
    settings_sync_facade.dart
    settings_transfer_workflow.dart
```

Custom Headers 与其余持久化小型用户设置一起进入 `preferences`。导入导出和 Sync
facade 共用同一套 export data、去重及执行流程，因此归入 `transfer`。

### 7.2 Domain models

```text
lib/features/settings/domain/models/
  preferences/
    auto_retry_settings.dart
    chat_defaults.dart
    custom_headers_config.dart
    font_size_settings.dart
    output_processing_settings.dart
  providers/
    llm_model_config.dart
    llm_provider_config.dart
    model_catalog_entry.dart
  prompts/
    fixed_prompt_sequence.dart
    memory_prompt.dart
    preset_prompt.dart
    prompt_message.dart
    prompt_message_placement.dart
    prompt_message_role.dart
    template_prompt.dart
  transfer/
    settings_export_codec.dart
    settings_export_data.dart
```

`domain/template_prompt_parser.dart` 保持原位。

### 7.3 Data

```text
lib/features/settings/data/
  chat_defaults_repository.dart
  providers/
    llm_model_config_repository.dart
    model_list_client.dart
  prompts/
    fixed_prompt_sequence_repository.dart
    preset_prompt_repository.dart
    sqlite_fixed_prompt_sequence_repository.dart
    sqlite_memory_prompt_repository.dart
    sqlite_preset_prompt_repository.dart
    sqlite_template_prompt_repository.dart
    template_prompt_repository.dart
```

`chat_defaults_repository.dart` 是唯一文件，不为它创建单文件目录。

### 7.4 Presentation widgets

```text
lib/features/settings/presentation/widgets/
  providers/
    forms/
      model_config_form_dialog.dart
      model_fetch_section.dart
      model_provider_form_dialog.dart
    lists/
      model_configs_list.dart
      provider_info.dart
      provider_info_body.dart
      provider_meta_chip.dart
      provider_model_info.dart
      provider_model_info_body.dart
      provider_model_tile.dart
      provider_tile.dart
  prompts/
    forms/
      editable_preset_prompt_item.dart
      fixed_prompt_sequence_form_dialog.dart
      memory_prompt_form_dialog.dart
      preset_prompt_editor_role.dart
      preset_prompt_form_dialog.dart
      preset_prompt_list_tile.dart
      template_prompt_form_dialog.dart
    lists/
      fixed_prompt_sequences_list.dart
      memory_prompts_list.dart
      preset_prompts_list.dart
      template_prompts_list.dart
  shared/
    settings_card_grid.dart
    settings_empty_state.dart
    settings_entity_card.dart
    settings_form_dialog_scaffold.dart
    settings_form_dialog_state_mixin.dart
    settings_helpers.dart
    settings_section_card.dart
  tabs/
    chat_defaults_section.dart
    header_form_dialog.dart
    network_settings_tab.dart
    other_settings_tab.dart
    output_processing_tab.dart
  transfer/
    import_confirm_dialog.dart
  settings_widgets.dart
```

`forms`、`lists` 只允许出现在具体业务切片下。原有全局 `form`、`list`、`section`、
`tab` 目录在迁移完成后消失。

### 7.5 Tests

```text
test/features/settings/
  application/
    preferences/
    providers/
    prompts/
    transfer/
  data/
    shared_preferences_repositories_test.dart
    providers/
    prompts/
  domain/
    models/
      preferences/
      providers/
      prompts/
      transfer/
    template_prompt_parser_test.dart
  presentation/
    settings_screen_test.dart
    settings_screen/
    widgets/
      providers/forms/
      tabs/
      transfer/
```

具体规则：

- `persisted_settings_controllers_test.dart` 和 `settings_tab_preferences_test.dart`
  进入 `application/preferences/`。
- LLM config/equivalence/catalog 测试进入 `application/providers/`。
- import、executor、sync facade、transfer workflow 测试进入
  `application/transfer/`。
- `shared_preferences_repositories_test.dart` 同时验证 Chat Defaults 与 LLM Model
  Config，保留在 `data/` 根目录且不拆分。
- SQLite repository 聚合测试进入 `data/prompts/`。
- domain 聚合测试按 preferences/providers/prompts/transfer 归位，不拆成逐模型文件。
- `settings_screen_test.dart` 及 case-files 进入 `presentation/`。

### 7.6 Import boundary 精确例外

Settings 的 7 条 application→data 存量例外只更新完整路径，不增加、删除、合并或
扩展例外：

```text
application/preferences/chat_defaults_controller.dart
  -> data/chat_defaults_repository.dart
application/prompts/fixed_prompt_sequences_controller.dart
  -> data/prompts/fixed_prompt_sequence_repository.dart
application/providers/llm_model_configs_controller.dart
  -> data/providers/llm_model_config_repository.dart
application/prompts/memory_prompts_controller.dart
  -> data/prompts/sqlite_memory_prompt_repository.dart
application/providers/model_catalog_workflow.dart
  -> data/providers/model_list_client.dart
application/prompts/preset_prompts_controller.dart
  -> data/prompts/preset_prompt_repository.dart
application/prompts/template_prompts_controller.dart
  -> data/prompts/template_prompt_repository.dart
```

`tool/architecture/import_boundary_checker.dart` 及对应架构测试必须同步更新。例外原因
保持原文，不得借路径迁移扩大 allowlist。

## 8. Media 目标结构

### 8.1 Data

```text
lib/features/media/data/
  libraries/
    default_media_library_factory.dart
    local_media_library.dart
    remote_media_library.dart
  scanning/
    media_directory_scanner.dart
    media_thumbnail_cache.dart
    media_thumbnail_generator.dart
    thumbnail_process_runner.dart
  http/
    media_http_handler_base.dart
    media_http_handler.dart
    media_image_http_handler.dart
    media_recursive_videos_handler.dart
    media_thumbnail_http_handler.dart
    media_video_http_handler.dart
    dto/
      media_file_item_dto.dart
```

Media application、domain 和生产 presentation 保持现状。

### 8.2 Tests

```text
test/features/media/
  application/
    models/
      media_library_contracts_test.dart
  data/
    libraries/
    scanning/
    http/
      dto/
  domain/
    media_file_classification_test.dart
    models/
  presentation/
    media_browser_navigation_test.dart
    pages/
    widgets/
```

具体规则：

- data 测试镜像 libraries/scanning/http/dto。
- `media_mime_types_test.dart` 实际验证 `domain/media_file_classification.dart`，
  重命名为 `media_file_classification_test.dart` 并移动到 domain。
- `media_browser_navigation_test.dart` 跨 browser tab 与 route pages，保留在
  presentation 根目录。
- page/widget 测试分别进入 `presentation/pages`、`presentation/widgets`。
- `test/features/media/helpers` 保持现状。

## 9. Sync 目标结构

### 9.1 Data

```text
lib/features/sync/data/
  http/
    http_sync_client_transport.dart
    http_udp_sync_server_transport.dart
    sync_http_handler.dart
    sync_http_server.dart
  udp/
    sync_multicast_lock.dart
    sync_udp_announcement_codec.dart
    sync_udp_discovery.dart
    sync_udp_scheduler.dart
    sync_udp_sessions.dart
    sync_udp_socket.dart
  security/
    cryptography_sync_crypto.dart
    secure_sync_pairing_repository.dart
```

`http_udp_sync_server_transport.dart` 归 `http`，因为它对 application 实现的是 server
transport 边界；其内部组合 UDP discovery 不改变主要职责。

### 9.2 Domain models

```text
lib/features/sync/domain/models/
  discovery/
    broadcast_prefix_length.dart
    discovered_server.dart
    network_interface_info.dart
    network_interface_utils.dart
  protocol/
    sync_message.dart
    sync_protocol_failure.dart
    sync_protocol_message.dart
    sync_protocol_version.dart
    sync_types.dart
  session/
    sync_pairing.dart
    sync_session.dart
```

### 9.3 Tests

```text
test/features/sync/
  application/
  data/
    http/
    udp/
    security/
  domain/models/
    discovery/
    protocol/
  presentation/widgets/
```

Sync application、ports、production presentation 和 feature-specific test fakes 不做
额外拆分，只随被测文件更新 import。

### 9.4 Composition 测试归属

当前 `test/features/sync/sync_screen_test.dart` 及其 case-files 实际验证
`lib/app/composition/sync_workspace_screen.dart`，应迁移为：

```text
test/app/composition/
  sync_workspace_screen_test.dart
  sync_workspace_screen/
    sync_workspace_screen_import_dialog_cases.dart
    sync_workspace_screen_render_cases.dart
    sync_workspace_screen_responsive_cases.dart
    sync_workspace_screen_test_helpers.dart
```

这是 ownership 修正，不把 production composition 移入 Sync feature。

## 10. Core widgets

```text
lib/core/widgets/
  dialogs/
    app_confirm_dialog.dart
    detail_display_dialog.dart
    rename_conversation_dialog.dart
  notification_bubble/
    notification_bubble.dart
    notification_bubble_context_ext.dart
    notification_bubble_data.dart
    notification_bubble_stack.dart
  adaptive_master_detail_layout.dart
  app_empty_state.dart
```

对应测试：

```text
test/core/widgets/
  notification_bubble/
    notification_bubble_accessibility_test.dart
  adaptive_master_detail_layout_test.dart
```

`lib/core/persistence` 不移动。当前目录只有 10 个命名清楚的文件，却有约 92 个生产、
测试或工具消费者；收益不足以抵消全仓路径扰动。

## 11. 共享测试 Helpers

```text
test/helpers/
  async/
    async_test_signals.dart
    async_test_signals_test.dart
    widget_test_animation.dart
    widget_test_animation_test.dart
  chat/
    controllable_chat_conversation_repository.dart
    fake_chat_generation_client.dart
    fake_history_repository.dart
    flaky_chat_conversation_repository.dart
  fixtures.dart
  integration_test_helpers.dart
  matchers.dart
  responsive_viewport_cases.dart
  test_harness.dart
```

剩余 5 个共享文件职责不同，继续创建 `common` 或 `utils` 目录只会增加跳转深度。
feature-specific helpers 保持在所属 feature。

## 12. Agent 日志规范

### 12.1 一次性清理

实施开始时先解析并确认仓库根目录，然后只删除根目录直接包含的 ignored `*.log`
文件。当前快照为 82 个。不得递归删除其他目录中的日志，不得删除应用 AppData 中的
`network.log`，不得触碰 `artifacts/` 中的构建产物。

这些日志均由 Agent 的测试、analyze、构建或诊断生成，可再生成；用户已明确确认
直接删除，不迁移到 legacy 目录。

### 12.2 统一目录

所有本地 Agent 开发日志写入：

```text
logs/
  fltest.log
  analyze.log
  build-windows.log
  build-android.log
  <task>-red.log
  <task>-green.log
```

规则：

1. `.gitignore` 新增 `/logs/`，删除未使用的 `.buildlog/`，保留 `*.log` 兜底。
2. `AGENTS.md` 的测试、analyze、构建和诊断规范明确禁止在仓库根目录生成日志。
3. PowerShell 命令写日志前使用 `New-Item -ItemType Directory -Force logs`。
4. 全量测试默认写 `logs/fltest.log`；red/green 日志使用能表达任务的文件名。
5. `logs/` 是 ignored、可再生成的临时产物，允许覆盖和清理。
6. `README.md` 中重复的本地测试命令同步使用 `logs/fltest.log`。
7. `.github/workflows/ci.yml` 保持根目录 `fltest.log`，因为 CI runner 是临时环境且
   该路径用于失败日志上传。
8. 应用运行时 `{AppData}/network.log` 不受此规则影响。

## 13. 迁移边界与不变量

每个批次都必须保持以下不变量：

- 除 import、export、文档路径、测试相对路径和 7 条精确 allowlist 路径外，不修改
  生产逻辑。
- 不改变类名、方法签名、Provider 名称、Repository 接口或 composition ownership。
- 不改变测试断言、测试数量和 case-file 注册关系；仅 ownership 修正允许测试文件
  重命名。
- `*_cases.dart` 继续不使用 `_test.dart` 后缀，避免被测试运行器重复发现。
- 不引入 `part` / `part of`。
- `widgets.dart` 与 `settings_widgets.dart` 不得导出错误层级或形成循环 export。
- Settings import boundary allowance 必须仍为恰好 7 条且全部被消费。
- 根目录日志删除与源码移动分开核对，不得使用递归宽泛删除命令。

## 14. 设计级实施顺序

实施计划应将工作拆成以下独立批次，每个批次单独提交并验证：

1. 删除根目录 Agent 日志，建立 `logs/` 文档与 ignore 规范。
2. Chat application/data 与对应测试。
3. Chat presentation widgets、screen tests、barrel 与对应文档路径。
4. Settings application/domain/data、测试及 7 条 architecture allowance。
5. Settings presentation widgets、screen tests 与 barrel。
6. Media data、测试镜像和两个明确的测试 ownership/name 修正。
7. Sync data/domain、测试镜像和 Sync Workspace composition 测试归属修正。
8. Core widgets 与对应测试。
9. 共享 test helpers 及所有消费方 import。
10. 全仓旧路径审计和最终静态、架构、测试验证。

实施计划可以在同一 feature 内合并相邻的低风险移动，但不得把全部 feature 压成一个
不可独立审查的大提交。

## 15. 验证与验收标准

### 15.1 每批验证

- 使用 `rg` 确认目标旧路径不再被 import/export 或文档引用。
- 对所有改动 Dart 文件执行 `dart format`，暂存后再执行格式检查。
- 运行该 feature 或组件的目标测试，输出写入 `logs/`。
- 运行 `dart run tool/check_import_boundaries.dart`。
- 检查 `git diff --check`。
- 使用 `git diff --summary` 与普通 diff 确认生产文件除路径/import 外没有语义变化。

### 15.2 最终验证

```powershell
dart run tool/check_import_boundaries.dart
flutter analyze --no-pub
flutter test --reporter compact
```

Flutter 测试必须按 `AGENTS.md` 的重定向规范写入 `logs/fltest.log` 并检查显式退出码。

### 15.3 最终验收

1. 本设计列出的目标目录和文件归属全部存在，旧目录不残留空壳。
2. `test/` 与 `lib/` 对应路径一致；明确列出的聚合测试例外位于共同父目录。
3. 热点目录不再包含 10 个以上平铺 Dart 文件；Chat application 的 9 个目录属于可
   接受的语义入口。
4. 架构门禁通过，Settings allowlist 仍为 7 条精确、已消费例外。
5. analyzer 与全量测试通过，测试用例没有因路径变更被遗漏或重复发现。
6. 仓库根目录不存在 Agent 生成的 `*.log`；后续本地日志全部进入 ignored `logs/`。
7. CI 日志上传、应用运行时日志和构建产物路径不受影响。
8. 没有生产文件拆分、跨 feature ownership 变化或未批准的架构整改。

## 16. 主要风险与控制

| 风险 | 控制措施 |
|---|---|
| 批量移动掩盖了意外逻辑修改 | 每批检查 rename summary 与普通 diff，生产内容只允许 import/export 变化 |
| 相对 import 层级变化导致遗漏 | 每批运行目标测试、boundary checker 和旧路径 `rg` 审计 |
| Settings allowlist 变 stale 或被扩大 | 同批精确替换 7 组 source/target 路径并运行架构测试 |
| case-files 被测试运行器重复发现 | 保持 `*_cases.dart` 后缀，只移动入口 `*_test.dart` |
| 测试文件移动后未被运行 | 对比迁移前后测试入口清单与最终全量测试 |
| 共享 helper 路径变更影响面过大 | 单独提交，集中更新全部消费者并运行全量测试 |
| 删除到非 Agent 日志 | 只解析仓库根目录直接 `*.log`，删除前列出精确目标，不递归 |
| 文档继续诱导 Agent 写根目录日志 | 同步修改 canonical `AGENTS.md` 和 README；CI 明确列为例外 |

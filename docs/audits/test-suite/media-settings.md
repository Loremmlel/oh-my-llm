# Media / Settings 测试审计

## 范围与数量

- 范围：`test/features/media/**` 与 `test/features/settings/**`，并对照对应的 `lib/features/media/**`、`lib/features/settings/**` 生产代码判断测试价值。
- 规模：media 43 个文件、9,707 个物理行，settings 33 个文件、9,162 个物理行；合计 76 个文件、18,869 个物理行（其中非空代码约 16,670 行）、639 个显式 `test` / `testWidgets` 声明。循环中的参数化 case 未展开计数。
- 方法：只读审计，未修改测试、未运行全量测试；净删行数按候选测试块和可随之移除的专用 helper 估算，不包含生产代码改动。

## 保留底线

- 设置迁移与持久化：保留已发布格式/历史格式的接受或显式拒绝、SQLite repository 往返、写入失败不发布幽灵状态，以及 `settings_tab_preferences_test.dart` 的 v1 迁移契约。
- 设置传输与安全：保留 v9 canonical document、旧版/未来版/malformed/未知 section 的拒绝、敏感导入/导出确认、摘要与错误脱敏、prepare 阶段零写入、stale preview、串行 writer、部分失败和 one-shot batch。
- LLM 配置：保留服务商等价键与导入合并的代表性契约、协议持久化值、Bearer/Anthropic/custom Header 的线上请求行为和错误脱敏。
- 模板语言：compiler/evaluator 属于有真实语法状态空间的核心代码；保留合法语法、稳定错误码/位置、类型检查、分支选择、默认值协调与空白语义。削减应发生在重复演示这些规则的 Widget 测试，而不是删掉 parser 边界矩阵。
- 媒体安全与协议：保留路径穿越在 scanner 和 HTTP 外边界的拒绝、HTTP Range 代表性区间与 416、DTO 兼容字段、远端资源不做 preflight 且仅使用 peer headers、缓存失效键、FFmpeg 成功链路与并发门控。
- 媒体关键用户流：保留目录浏览、图片打开/翻页、视频初始化/失败重试/关闭释放，移动端双击/长按/拖动各一条端到端路径，桌面键盘/全屏/滚轮各一条 wiring 路径，以及关键控件、错误和动态反馈的语义可达性。

## Findings（按预计净删行数降序）

shrink: 桌面视频输入在 463 行生产 controller 上堆了 997 行白盒状态机测试，又在页面层重复方向键、静音、全屏、触摸负例、滚轮和失焦释放；repeat/up、pending/hold、暂停/结束/错误和多种取消来源分别立例，维护成本远高于新增分支价值，预计净删约 550 行。保留 controller 层的短按/长按互斥、一个取消收口、主要快捷键、全屏失败、自动隐藏 hold、滚轮方向与节流等代表测试，页面层只保留焦点/弹层/关闭顺序和每类输入一条 wiring smoke。 [test/features/media/presentation/pages/desktop_video_interaction_controller_test.dart:169, test/features/media/presentation/pages/video_player_desktop_test.dart:195]

shrink: SettingsScreen 对 provider/model、preset、template、memory、fixed sequence 每种实体逐一重复 create/edit/delete，且保存正确性已由 controller/repository 覆盖；这些长链 Widget 测试主要绑定按钮文案、展开状态和表单布局，预计净删约 420 行。合并成“provider+model 一条”和“每类 prompt 至少一条创建/持久化”主流程，仅为排序、变量 reconcile 和复制文档等独有行为留专项测试。 [test/features/settings/presentation/settings_screen/settings_screen_models_and_prompts_cases.dart:40, test/features/settings/presentation/settings_screen/settings_screen_fixed_prompt_sequences_cases.dart:20]

shrink: 170 行 `LlmProviderConfigsController` 对应 921 行测试，纯 `mergeImportedLlmProviders` 的四个合并契约又在 controller 路径重复七遍，add/update/sort/bulk/no-op 也被拆成逐方法样例，预计净删约 400 行。保留纯 merger 的 ID 优先、等价键、协议隔离、modelName 去重四条，以及 controller 的组合 CRUD 持久化、批量去重计数和写失败不发布状态各一条。 [test/features/settings/application/providers/llm_model_configs_controller_test.dart:49, test/features/settings/application/providers/llm_model_configs_controller_test.dart:264, test/features/settings/application/providers/llm_model_configs_controller_test.dart:382]

shrink: 设置传输在 catalog、production contract、coordinator、facade 四层反复证明“新 fake participant 无需分支”、分组顺序/敏感性、allowedGroups 和 local-only key；独立 catalog 不改变生产 snapshot 更是由对象隔离天然成立，预计净删约 300 行。保留 catalog 自身的唯一 key/order/type 检查、一个 facade 端到端扩展性测试、production canonical snapshot，以及 coordinator 的安全与事务契约；删除其余跨层同义断言和专用 fake。 [test/features/settings/application/transfer/settings_transfer_catalog_test.dart:9, test/features/settings/application/transfer/settings_transfer_catalog_contract_test.dart:161, test/features/settings/application/transfer/settings_transfer_catalog_contract_test.dart:409, test/features/settings/application/transfer/settings_transfer_coordinator_test.dart:431, test/features/settings/application/transfer/settings_sync_facade_test.dart:44]

shrink: 移动视频的双击、长按、横拖和音量边界同时在 `VideoPlaybackController`、`MobileVideoInteractionController` 与整页 Widget 中断言，页面测试还重复 controller 已覆盖的 pause/end guard、cancel 后状态和 clamp，预计净删约 300 行。保留共享播放核心的初始化/seek/lease/静音代表契约、移动 controller 的每种手势状态转换，以及页面层每类 GestureDetector 一条端到端 wiring；删除相同边界在第二、第三层的再次穷举。 [test/features/media/presentation/pages/video_playback_controller_test.dart:37, test/features/media/presentation/pages/mobile_video_interaction_controller_test.dart:71, test/features/media/presentation/pages/video_player_page_test.dart:219]

shrink: 视频无障碍套件把键盘播放、seek、长按、音量、三秒隐藏和全屏失败的业务结果再次测试，并精确锁定 tooltip/hint 文案、节点消失时点和完整 Tab 顺序；前半已被交互套件覆盖，后半对无障碍树实现细节脆弱，预计净删约 180 行。保留 surface/加载/错误的唯一语义、slider enabled/disabled、一个 live region 去重、一个键盘等价操作和焦点可达 smoke。 [test/features/media/presentation/pages/video_player_accessibility_test.dart:113, test/features/media/presentation/pages/video_player_accessibility_test.dart:212, test/features/media/presentation/pages/video_player_accessibility_test.dart:319, test/features/media/presentation/pages/video_player_accessibility_test.dart:479]

delete: 多个 model 测试只验证构造器默认值、布尔 getter、`Equatable.props`/枚举映射或一行派生属性，不能比 Dart 类型检查和调用这些属性的上层行为多发现有价值回归；协议枚举 round-trip 还在 model/provider 两组重复，预计净删约 220 行。保留兼容默认值、JSON canonical/round-trip、未知协议拒绝、prompt placement 过滤和真正有业务分支的摘要/截断边界。 [test/features/settings/domain/models/providers/llm_configs_test.dart:21, test/features/settings/domain/models/preferences/settings_value_objects_test.dart:10, test/features/settings/domain/models/prompts/template_prompt_test.dart:5, test/features/settings/domain/models/prompts/prompt_models_test.dart:7]

shrink: `TemplatePromptFormDialog` 再次覆盖 compiler/evaluator 已穷举的嵌套条件、非法正文、select 默认回落、非法数字和诊断文案，还用“页面不存在预览文字”锁死非功能，预计净删约 150 行。保留一条合法 select 提交、一条带行列诊断不提交，以及“暂时无效后修复仍保留输入”的表单状态契约；语法说明只做展开 smoke，不逐字校验说明内容。 [test/features/settings/presentation/widgets/prompts/forms/template_prompt_form_dialog_test.dart:91, test/features/settings/presentation/widgets/prompts/forms/template_prompt_form_dialog_test.dart:109, test/features/settings/presentation/widgets/prompts/forms/template_prompt_form_dialog_test.dart:187, test/features/settings/presentation/widgets/prompts/forms/template_prompt_form_dialog_test.dart:214, test/features/settings/presentation/widgets/prompts/forms/template_prompt_form_dialog_test.dart:297]

shrink: 媒体 route 恢复页把图片/视频的缺 path、错扩展名、失效 session、解析失败和“不创建 bindings”逐项展开，两个返回栈形状也重复整套 harness；这些分支共享同一恢复页并大量绑定具体文案，预计净删约 150 行。用表驱动保留一条图片非法、一条视频 session/resolve 失败和两种 Navigator 栈行为，同时保留合法图片 target 与合法视频独立 bindings 会话。 [test/features/media/presentation/pages/media_route_pages_test.dart:97, test/features/media/presentation/pages/media_route_pages_test.dart:123, test/features/media/presentation/pages/media_route_pages_test.dart:185, test/features/media/presentation/pages/media_route_pages_test.dart:277, test/features/media/presentation/pages/media_route_pages_test.dart:347]

delete: media 的小值对象/布局快照里存在明显恒真或实现镜像：默认字段和 `hasThumbnail` 原样返回、source/request 的 Equatable 字段、同一 context 连算三次必然相等、density switch 的每个常量逐字段抄写、工厂仅核对 Flutter controller 构造器，预计净删约 150 行。保留 URI scheme/headers 防御性复制、`formattedSize` 边界、文字缩放导致行高增长及真实 grid viewport smoke。 [test/features/media/domain/models/file_item_test.dart:6, test/features/media/application/models/media_library_contracts_test.dart:7, test/features/media/presentation/models/media_grid_layout_spec_test.dart:14, test/features/media/presentation/models/media_grid_tile_metrics_test.dart:53, test/features/media/presentation/pages/media_video_controller_factory_test.dart:7]

shrink: 缩略图生成器对同一失败类别分别测试非零退出、`ProcessException`、其它异常、字符串/字节 stderr，并对多个无法解析时长逐项校验精确错误文案，偏向 subprocess 适配实现而非用户契约，预计净删约 140 行。保留图片/视频各一条成功、并发门控、版本检测缓存、短/长视频 seek 选择，以及版本探测/时长探测/提取失败各一个代表错误。 [test/features/media/data/scanning/media_thumbnail_generator_test.dart:175, test/features/media/data/scanning/media_thumbnail_generator_test.dart:251, test/features/media/data/scanning/media_thumbnail_generator_test.dart:279, test/features/media/data/scanning/media_thumbnail_generator_test.dart:305, test/features/media/data/scanning/media_thumbnail_generator_test.dart:345, test/features/media/data/scanning/media_thumbnail_generator_test.dart:369]

shrink: 四组 `VersionedJsonStore` controller 测试重复 missing、corrupt、save+revive、rejected write 四件事，而这些 controller 除类型/键外只是同一 store 的机械绑定，预计净删约 130 行。保留一个共享 store 代表的加载/保存/失败契约，并仅为 CustomHeaders 的索引增删改、FontSize 的 `updateLocal` 和 AutoRetry 退出支持的裸 JSON 留专项测试。 [test/features/settings/application/preferences/persisted_settings_controllers_test.dart:48, test/features/settings/application/preferences/persisted_settings_controllers_test.dart:152, test/features/settings/application/preferences/persisted_settings_controllers_test.dart:219, test/features/settings/application/preferences/persisted_settings_controllers_test.dart:270]

shrink: scanner、LocalMediaLibrary、HTTP list/image/thumbnail handler 对根目录、中文路径、不存在/空目录和元数据重复做三层集成；安全穿越应保留在解析层与最外 HTTP 边界，但普通成功排列无需每层穷举，预计净删约 120 行。保留 scanner 排序/隐藏/递归、library 错误映射与 cache、HTTP 中文路径端到端和 path traversal/404，各层其余正例收敛为一个代表。 [test/features/media/data/scanning/media_directory_scanner_test.dart:29, test/features/media/data/libraries/local_media_library_test.dart:70, test/features/media/data/http/media_http_handler_test.dart:41, test/features/media/data/http/media_image_http_handler_test.dart:49, test/features/media/data/http/media_thumbnail_http_handler_test.dart:134]

shrink: 模型拉取在 client、workflow、form 三层重复 URL 派生、loading/error/success 与协议透传；provider form 又循环每个协议验证同一 Dropdown/submit wiring，预计净删约 120 行。保留 client 的鉴权/custom headers/错误映射、workflow 的 suffix 归一化与稳定失败、form 的一次成功选择和一次失败重试，再用一个非默认协议代表表单透传。 [test/features/settings/data/providers/model_list_client_test.dart:45, test/features/settings/application/providers/model_catalog_workflow_test.dart:9, test/features/settings/presentation/widgets/providers/forms/model_config_form_dialog_test.dart:151, test/features/settings/presentation/widgets/providers/forms/model_provider_form_dialog_test.dart:123]

shrink: media grid/path/density Widget 测试多处以多个 viewport 只断言 `takeException() == null`，并精确统计初帧、缩放、切密度时 resolver 调用次数；这类缓存实现断言容易因预取/重建策略变化而误报，预计净删约 100 行。保留两个极端 viewport 的可达性、长文本/大字号、一条 density 选择持久化、路径 breadcrumb 的 pointer+keyboard，以及切密度后锚点仍可达的用户结果。 [test/features/media/presentation/widgets/media_grid_view_test.dart:88, test/features/media/presentation/widgets/media_grid_view_test.dart:142, test/features/media/presentation/widgets/media_grid_density_actions_test.dart:41, test/features/media/presentation/widgets/media_path_bar_accessibility_test.dart:30]

shrink: 输出处理 Tab 对空态/已有卡片、新增/编辑、switch、排序、确认/取消删除逐项做 Widget CRUD，而 controller 与值对象已验证状态写入；“取消删除后仍在”主要验证 Flutter Dialog 默认行为，预计净删约 60 行。保留非法正则、一条新增、一条重排/启停和一条确认删除的可观察流程。 [test/features/settings/presentation/widgets/tabs/output_processing_tab_test.dart:61, test/features/settings/presentation/widgets/tabs/output_processing_tab_test.dart:105, test/features/settings/presentation/widgets/tabs/output_processing_tab_test.dart:196]

delete: “多次随机后至少一次顺序变化”依赖不可注入的 `Random`，理论上仍会偶发失败，而且实质是在复测 SDK `List.shuffle`；是否返回完整 playlist/首项已由 startShuffle 主流程覆盖，预计净删约 32 行。删除概率性顺序断言，保留列表成员不丢失、首项路径和 next/previous 边界；若随机策略未来成为产品契约，再注入 seeded Random 做确定性测试。 [test/features/media/application/shuffle_playback_controller_behavior_test.dart:176]

net: -3522 lines, -0 deps possible.

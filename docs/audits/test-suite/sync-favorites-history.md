# Sync、Favorites、History 测试审计

## 范围与数量

- 审计范围：`test/features/sync/**`、`test/features/favorites/**`、`test/features/history/**`，并对照了对应生产代码、`test/features/chat/application/history/history_pagination_controller_test.dart` 以及共享分页/自适应网格测试。
- 静态规模：Sync 19 个文件、3,087 行、92 处测试声明；Favorites 15 个文件、3,301 行、116 处测试声明；History 7 个文件、1,333 行、44 处测试声明。合计 41 个文件、7,721 行、252 处声明；参数化注册会使实际运行 case 更多。
- 口径：只审计可删除复杂度、重复证明、恒真断言和脆弱实现绑定；不把正确性缺陷混入清单。本报告未修改测试，也未运行全量测试。
- 核心判断：主要浪费来自同一契约在 repository、application controller、整页 widget 三层重复验证，而不是 Sync 安全测试本身。

## 保留底线

- Sync 当前生产协议是 v4，v3 是必须显式拒绝的旧版本；应保留 typed message、稳定 group ID、结构化 transfer document、旧版/未来版/malformed 拒绝、requestId 匹配和 HTTP public error 映射的最低层契约。
- 保留 AES-GCM 对 AAD/密文篡改的拒绝、secret 只进入 secure store、孤立/损坏 pairing 清理、匿名请求在 facade 前被拒绝、服务端依据本地 catalog 重算敏感性、未知 group 拒绝、session/nonce 重放防护，以及关键资源关闭竞态。
- Favorites 保留一条完整 SQLite round-trip、系统收藏夹不可删除、collection 外键和稳定排序、一个真实分页边界、批量 move/delete、三种收藏夹删除处置及事务回滚；application 层只需各保留一个可观察的 revision 失效、页码补齐/收藏夹回退和查询失败保留旧窗口契约。
- History 搜索必须保留“标题 + 所有分支用户消息可命中、assistant 回复不可命中”；异步查询的 latest-wins、失败保留 committed window、rename/delete 后重查等状态机契约应由 `HistoryPaginationController` 测试独占，页面层只保留少数 URL 同步、错误渲染、dispose 和用户操作接线。
- 键盘、系统返回、路由可序列化 ID、inline error、危险删除确认等用户可见边界仍保留代表测试；共享分页栏、共享自适应网格自身已经覆盖的渲染行为不在每个 feature 重跑。

## Findings（按预计净删行数降序）

delete: 删除约 246 行 History 异步整页重复 case：清空在途搜索、A/B/C latest-wins、搜索态 rename、delete 防复活、busy 翻页都已在 controller 层以受控 Future 逐项覆盖，widget 版本又重复驱动 TextField、overlay 和路由，慢且更脆弱。保留页面层“成功后才 replace URL”“失败回滚 URL/显示 inline error”“外部 deep link”“dispose 不改路由”，状态机以 `HistoryPaginationController` 的同名用例为唯一 owner。 [test/features/history/history_screen/history_screen_async_query_cases.dart:215 `在途非空搜索后立即清空时非空结果不能回写 URL 或列表`; test/features/history/history_screen/history_screen_async_query_cases.dart:257 `A 在途、B pending、C latest 时只有 C 最终更新可见窗口和 URL`; test/features/history/history_screen/history_screen_async_query_cases.dart:324 `搜索态 rename 后等待刷新，退出匹配的条目按查询结果消失`; test/features/history/history_screen/history_screen_async_query_cases.dart:383 `delete 后刷新不会被删除前在途查询复活`; test/features/history/history_screen/history_screen_async_query_cases.dart:447 `busy 时分页操作被忽略，搜索输入仍可用`; test/features/chat/application/history/history_pagination_controller_test.dart:76]

delete: 删除约 143 行 SQLiteFavoritesRepository 的重复 CRUD/分页证明：第二份完整 `loadById` 字段枚举、单条 delete、单条 move、第二份 `findByAssistantContent`、单条页和 51 条循环翻页分别被首个完整 round-trip、批量 mutation、21 条边界和 widget 翻页覆盖；51 条 while-loop 实质是在重复验证 SQLite `LIMIT/OFFSET`。保留“完整字段含 nullable”“重复 id 更新”“21 条边界 + 稳定 tie-break + collection 过滤”“批量 delete/move + FK 拒绝”代表测试。 [test/features/favorites/data/sqlite_favorites_repository_test.dart:134 `delete 后记录不再出现`; test/features/favorites/data/sqlite_favorites_repository_test.dart:145 `moveMany 更新归属并刷新归属时间，移回系统未分类`; test/features/favorites/data/sqlite_favorites_repository_test.dart:205 `两条记录时按 ID 精确读取完整字段，缺失 ID 返回 null`; test/features/favorites/data/sqlite_favorites_repository_test.dart:274 `单条收藏返回一页且总数为 1`; test/features/favorites/data/sqlite_favorites_repository_test.dart:303 `51 条连续翻页无重复无遗漏，末页补齐剩余条目`; test/features/favorites/data/sqlite_favorites_repository_test.dart:376 `findByAssistantContent 命中返回完整记录、未命中返回 null`]

delete: 删除约 83 行 SqliteCollectionsRepository 内部重复：通用 save/delete 生命周期被 UPSERT 回归和 typed delete 覆盖，`loadSummaries` 排序与前面的 `loadAll 与 loadSummaries 同序` 完全重叠，两份“重命名含收藏”都在证明同一个 `ON CONFLICT DO UPDATE` 回归，删除不存在 ID 的 no-op 没有关键数据契约。保留 UPSERT 不破坏归属、双 reader 同序、聚合 count/recentAssignedAt、三种 typed delete 与事务回滚。 [test/features/favorites/data/sqlite_collections_repository_test.dart:44 `save/delete 生命周期：保存、按 id 更新、删除普通收藏夹`; test/features/favorites/data/sqlite_collections_repository_test.dart:153 `普通夹按名称排序、同名按 id tie-break，系统夹恒置顶`; test/features/favorites/data/sqlite_collections_repository_test.dart:253 `rename 含收藏的收藏夹后归属与计数不变`; test/features/favorites/data/sqlite_collections_repository_test.dart:418 `删除不存在的收藏夹为 no-op 返回 0`]

shrink: 将约 68 行“每个 mutation 都让内部 revision 精确 +1”和两份 by-ID reader 刷新测试收缩为一个可观察行为测试；revision 是失效机制而非业务结果，逐方法断言 1、2、3、4、5 会把重构锁死，且 `favorites_controller_test.dart` 与 `favorites_library_controller_test.dart` 又重复 rename/move。保留“成功 mutation 后 by-ID 与 summaries 更新”和“repository 抛错后旧 reader 不被伪刷新”各一个代表用例。 [test/features/favorites/application/favorites_library_controller_test.dart:50 `初始 revision 为 0，成功的 add/rename/create/move/remove 各递增一次`; test/features/favorites/application/favorites_library_controller_test.dart:74 `批量删除与删除收藏夹同样逐次递增 revision`; test/features/favorites/application/favorites_library_controller_test.dart:112 `query readers 跟随 revision 失效：by-ID 与 summaries 同步更新`; test/features/favorites/application/favorites_controller_test.dart:48 `rename/move/remove 后 by-ID 状态随 revision 同步更新`]

delete: 删除约 63 行 `Favorite` 的 getter/copyWith 自证文件；`hasReasoning` 和 `displayTitle` 是单表达式 getter，`copyWith` 用传入值再断言传出值，且这些字段已经被 SQLite round-trip、详情展示、移动流程真实消费。以 repository 完整 round-trip 和详情页 reasoning/title 代表测试替代。 [test/features/favorites/domain/favorite_test.dart:1]

delete: 删除约 57 行真实 loopback UDP smoke 的默认测试负担；该 case 已被 CI 明确 `--exclude-tags=udp` 排除，依赖 OS socket/防火墙且失败要等双重 2 秒 timeout，因此既不是稳定门禁，也重复 deterministic socket lifecycle + announcement codec 的接线。保留 fake socket 生命周期和 codec 契约；真实 UDP 改为发布前人工/平台 smoke，而非日常 `flutter test`。 [test/features/sync/data/udp/sync_udp_discovery_test.dart:1; .github/workflows/ci.yml:51; test/features/sync/data/udp/sync_udp_discovery_lifecycle_test.dart:44]

delete: 删除约 44 行 History 对共享分页控件的二次验证：零条不渲染、单页不可前进、分页栏固定、越界 jump 都已由 `AppPaginationBar`/`AppPaginatedListShell` 和 pagination controller 覆盖。History 只保留“下一页接线”“切容量清选择”“外部 route 清选择”“push/pop 恢复窗口与滚动”这些 feature-owned 行为。 [test/features/history/history_screen/history_screen_pagination_bar_cases.dart:9 `总条数为零时分页栏完全不渲染`; test/features/history/history_screen/history_screen_pagination_bar_cases.dart:16 `仅一页时翻页控件不可用`; test/features/history/history_screen/history_screen_pagination_bar_cases.dart:28 `分页栏固定在列表底部且不随列表滚动`; test/features/history/history_screen/history_screen_pagination_bar_cases.dart:53 `跳转越界页码夹取到末页`; test/core/widgets/pagination/app_pagination_bar_test.dart:200; test/core/widgets/pagination/app_paginated_list_shell_test.dart:70]

delete: 删除约 37 行只断言 `takeException() == null`/文本存在的响应式 smoke；History 宽屏用例甚至没有测量“合理限宽”，Favorites 三档循环重复共享 `AppAdaptiveGrid` 自身测试，只会增加整页 pump 次数。保留共享 adaptive-grid 的宽度算法测试、History 320px 边界和 Favorite detail 对 `AppContentWidths.readable` 的实际尺寸断言。 [test/features/history/history_screen/history_screen_responsive_cases.dart:24 `1440px 宽视口下内容合理限宽不无限拉伸`; test/features/favorites/favorites_screen_basics_cases.dart:169 `窄中宽三档父宽下网格连续布局且不溢出`; test/core/widgets/adaptive_grid/app_adaptive_grid_test.dart:17; test/features/favorites/favorites_screen_detail_cases.dart:232]

delete: 删除约 36 行 `SyncClientState` 的形状/Equatable 实现测试；`props.join()` 不包含字符串 `token`/`secret` 并不能证明敏感值不会进入状态，构造函数本就没有这些字段，因此该安全断言近似恒真；Set 插入顺序相等只验证 Equatable props 的实现细节。真正的安全边界由 pairing repository、协议 coordinator 与日志/序列化边界测试承担。 [test/features/sync/application/sync_client_controller_test.dart:93 `客户端安全状态不会包含 pairing code 或 session secret`; test/features/sync/application/sync_client_controller_test.dart:113 `分组状态的等价比较按稳定 ID 排序而不依赖集合迭代顺序`]

shrink: 将 FavoriteBrowserController 的初始默认值、第一页、指定第二页、越界页四个读取型 case 收缩为一个 route 边界用例；底层分页排序已有 repository 测试，整页 URL/翻页已有 widget 测试，controller 应集中保留 mutation 后补齐、删除当前收藏夹回退和失败保留旧窗口。预计净删约 34 行。 [test/features/favorites/application/favorite_browser_controller_test.dart:125 `初始状态为未初始化的系统夹空窗口`; test/features/favorites/application/favorite_browser_controller_test.dart:137 `loadRoute 加载指定收藏夹的当前页窗口`; test/features/favorites/application/favorite_browser_controller_test.dart:149 `loadRoute 指定容量与页码时加载对应窗口`; test/features/favorites/application/favorite_browser_controller_test.dart:165 `route 页码越界时按真实总数夹取到最后一页`]

shrink: 删除散落在四条流程里的重复“点取消后数据仍在”尾段或整条专用 case，保留每个危险动作确实先出现确认框，以及一条代表性的取消 no-op；取消按钮本身由共享确认对话框负责，不值得在卡片、详情、选择工具栏、History overflow 各完整 pump 一遍。预计净删约 34 行。 [test/features/favorites/favorite_collection_tile_cases.dart:163 `取消删除保留空收藏夹`; test/features/favorites/favorites_screen_detail_cases.dart:143 `溢出菜单删除需确认且确认后返回收藏总览`; test/features/favorites/favorites_screen_selection_cases.dart:146 `Delete 键对选中项发起删除确认且取消不生效`; test/features/history/history_screen/history_screen_actions_cases.dart:143 `overflow 单项删除需确认且取消不删除`]

delete: 删除约 25 行广播前缀默认/恢复的跨层重复：domain 已完整覆盖 `fromStorage(null/invalid/8/16/24)`，widget 点击 /16 已覆盖 UI→provider 接线，provider 只需保留一次 select 后 state 与 SharedPreferences 写入；再测“无存储”“非法值”和 widget 从存储 16 恢复是在三层证明同一表达式。 [test/features/sync/application/broadcast_prefix_length_provider_test.dart:20; test/features/sync/presentation/widgets/interface_selector_test.dart:67 `SharedPreferences 存 16 时默认选中 /16`; test/features/sync/domain/models/discovery/broadcast_prefix_length_test.dart:42]

delete: 删除约 23 行通过 `getRect` 锁定 popup 相对位置的菜单锚点测试；菜单能从该按钮打开且所有动作可执行已由相邻 case 覆盖，相对坐标受 Material overlay/主题/字体变化影响，并不保护收藏业务。保留“空夹显示删除、非空夹不显示删除”和 rename/delete 行为测试。 [test/features/favorites/favorite_collection_tile_cases.dart:51 `溢出菜单从更多操作按钮处弹出`]

shrink: 将 UDP 公告 18 个逐字段 microtest 收缩到约 6 个等价类并在单个参数表内循环：非法 UTF-8/JSON、非对象、错误 app/version、非法 protocol range、非法 endpoint/identity；当前 18 次注册穷举每个 null/type/范围排列，维护成本大于发现能力。保留一次手工合法 envelope 和一次 encode/decode round-trip，预计净删约 20 行。 [test/features/sync/data/udp/sync_udp_announcement_codec_test.dart:45 `decode 对非法公告一律返回 null`]

delete: 删除约 17 行 controller 层再次通过真实 HTTP POST 证明旧协议返回 upgrade-required；同一拒绝已在 version policy、codec 的 public `unsupportedProtocol` 以及 `SyncHttpServer` 边界覆盖，controller 版本只增加端口和 JSON 解析成本。保留 codec + HTTP server 两层，另保留 controller 的匿名请求“不泄漏 API key/不计数”安全集成。 [test/features/sync/application/sync_server_controller_test.dart:301 `POST 旧协议请求返回 public unsupportedProtocol`; test/features/sync/domain/models/protocol/sync_protocol_message_test.dart:200; test/features/sync/data/http/sync_http_server_test.dart:19]

shrink: 把 Favorite detail 的“无推理面板”负例折进普通详情内容测试，用一条 `findsNothing` 断言即可；当前专用 case 重做整套数据库、路由和页面 pump，仅验证 `if (assistantReasoningContent.isNotEmpty)` 的反分支。保留有推理时展开并显示内容的正向集成，预计净删约 15 行。 [test/features/favorites/favorites_screen_detail_cases.dart:280 `详情页展示用户消息与模型回复内容`; test/features/favorites/favorites_screen_detail_cases.dart:299 `有推理内容时展示可展开的推理面板`; test/features/favorites/favorites_screen_detail_cases.dart:323 `无推理内容时不展示推理面板`]

delete: 删除约 14 行同步数据路径下“搜索成功后 URL 带 q”的重复 case；异步页面用例已经更强地证明成功前 URL 不变、成功后才 replace，搜索文件应只保留标题/用户/assistant/分支匹配规则和清空/选择行为。 [test/features/history/history_screen/history_screen_search_cases.dart:87 `搜索生效后以 replace 更新当前 location 携带关键词`; test/features/history/history_screen/history_screen_async_query_cases.dart:72 `搜索成功前 URL 保持旧值，成功后才 replace`]

delete: 删除约 11 行 Favorites 整页“21 条默认第一页”的独立 case；紧随其后的“翻到第 2 页并写 URL”用相同 21 条 fixture，已同时证明默认 20、页数、页间内容切换和路由写入，repository 也覆盖首屏排序。保留更强的第二页 case。 [test/features/favorites/favorites_screen_pagination_cases.dart:98 `21 条收藏默认每页 20 条且分页栏显示总页数`; test/features/favorites/favorites_screen_pagination_cases.dart:109 `翻到第 2 页显示剩余条目并把页码写入 URL`]

delete: 删除约 6 行精确断言 Favorites SharedPreferences key 字面量的测试；key 是否与 History 相同可由两个常量定义直接审查，测试只会在合法重命名时制造无行为回归。保留默认、合法恢复、非法回退和 save 行为。 [test/features/favorites/application/favorites_browse_preferences_controller_test.dart:105 `Favorites 容量 key 不与 History 共用`]

## 建议实施顺序

1. 先删 History async/controller 跨层重复、共享分页重复和恒真响应式 smoke；这是最大且风险最低的一批，保留的 controller 测试仍覆盖竞态。
2. 再收缩 Favorites repository/application 三层重复；每次只改一个层级，先跑对应单文件测试，再跑 `favorites_screen_test.dart`。
3. 最后处理 Sync；先删恒真 state、重复旧协议和 preference/UI 重复，再缩 UDP 非法矩阵。安全底线测试不得与减负提交混删。
4. 每批记录实际测试数、总耗时和净删行；若速度改善主要来自 widget case，应优先继续按“最低 owner 层 + 一个 UI 接线”原则收口，而不是削弱协议/持久化边界。

net: -976 lines, -0 deps possible.

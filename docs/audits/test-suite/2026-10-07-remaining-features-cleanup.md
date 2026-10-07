# 剩余功能测试清理结果（2026-10-07）

本轮扫描 `test/features/favorites`、`history`、`media`、`settings`、`sync` 的 118 个 Dart 文件、93 个自动发现入口。基线为 Agent / Chat 清理提交 `19dddebdbe08e4c5356b6126721898ded1b4ba15`。本轮仅修改这五个目录的测试和本报告，不修改生产 Dart 代码；按用户要求在 `test/remaining-features-cleanup` 本地提交，不创建 PR。

## 清理依据与契约归属

| 问题 | 处理 | 继续承担契约的测试 |
| --- | --- | --- |
| 收藏详情的菜单、正文、无推理、所属收藏夹入口分别重复挂载页面 | 正文与无推理合入元数据；移动成功后实际进入目标夹；删除流程保留取消和确认 | `favorites_screen_detail_cases.dart` 保留来源路由、缺失来源不可跳转、移动归属和推理展开；窄屏检查内容、入口可达与溢出，移除可变像素限宽断言 |
| 收藏夹保留名、改名成功、菜单存在、删除取消与确认各重复初始化 | 合并为输入修复、取消后重新打开、取消删除后确认删除的连续流程 | `favorite_collection_tile_cases.dart`、`favorites_screen_basics_cases.dart`；新建后实际按 Enter 打开，替代追踪内部 Focus / State |
| 删除收藏夹用“包含数字 3”证明数量，另测 widget 树中的文字顺序 | 合入真实移动流程，精确验证“中有 2 项收藏”和目标排除自身；移除树序实现断言 | `favorites_screen_collection_delete_cases.dart` 继续验证默认移入未分类、其他目标、连同收藏删除、新建目标仍需确认、失败后可重试 |
| 两个收藏 controller 文件重复验证 by-ID 改名、移动、删除 | 集中到 library controller；提前读取摘要再变更，保证失效机制真实接受检验 | `favorites_library_controller_test.dart` 同时检查条目与收藏夹计数；系统夹过滤、持久失败不发布 revision 等独立契约保留 |
| 历史页面重演搜索角色与分支矩阵 | 页面保留防抖输入、清除恢复和真实列表接线；删除重复搜索矩阵和专用树 fixture | `history_page_query_adapter_test.dart` 验证助手回复不匹配；`sqlite_chat_conversation_repository_test.dart` 验证非选中用户分支。两个 owner 均在上一轮 Chat 范围内，本轮只读取 |
| 历史搜索失败和失败重试分别准备相同窗口 | 合为失败时旧列表 / URL 保留、原目标重试成功才更新 URL | `history_screen_async_query_cases.dart`；迟到结果、深链恢复、加载中输入等不同异步机制仍独立保留 |
| 历史普通跳转、翻页、选择快捷键分别重复准备 | 跳转目标 ID 合入返回后保留滚动；下一页内容合入清空选择；Ctrl+A / Esc / Ctrl / Shift 合成选择流程 | `history_screen_pagination_bar_cases.dart` 与 `history_screen_actions_cases.dart`；长按、右键、系统返回、删除确认 / 取消、外部路由仍保留 |
| 设置页面 tab 恢复 / 切换与响应式 smoke 重复 | 单一窄屏全部分组流程同时检查恢复；真实新增服务商改用窄屏；删除独立 tab cases 文件 | `settings_screen_responsive_cases.dart` 和服务商保存流程。共享布局的边界矩阵继续归 `test/core/widgets/adaptive_master_detail_layout_test.dart` |
| 预设和固定序列的简单创建与插入顺序流程重复 | 保留较强的插入流程，补正文、顺序、注入位置和保存后列表断言 | `settings_screen_models_and_prompts_cases.dart`、`settings_screen_fixed_prompt_sequences_cases.dart` |
| 模板变量防抖在整个设置页面与表单层重演 | 防抖、无效正文保留默认值、修复和替换变量后保存归入表单流程；页面保留实际持久化接线 | `template_prompt_form_dialog_test.dart`，默认选项以提交数据验证，移除 FormField 内部值读取 |
| 无效正则与有效保存分别打开同一空表单 | 无效提交不落库，修正后保存到列表并验证规则正文 | `output_processing_tab_test.dart` |
| 传输 registry 元数据、精确导出与本地专属字段排除重复 | 分组顺序 / 敏感性合入精确导出；去掉同一个 Riverpod 实例的身份断言和重复键集合断言 | `settings_transfer_production_contract_test.dart` 保留完整 canonical 内容、导入导出、合并策略和空替换；页面敏感导出取消 / 确认可连贯验证，保密和无写入断言保留 |
| 媒体尺寸测试挂整套 DB / Provider，并抄写生产行高公式 | 最小 MaterialApp 验证文字放大、4:3 缩略图和零宽度；删除只检查开发者非法输入 assert 的测试 | `media_grid_tile_metrics_test.dart`；实际布局、不同密度和可访问性矩阵仍归现有 widget 测试 |
| 播放焦点由读取祖先 Focus 判断；图集起始页、翻页、下一视频和退出各重复挂载 | 实际发方向键 / Space 检查 seek / pause；图集从非零页翻到下一页；打开视频后关闭并检查退出次数 | `video_player_desktop_test.dart`、`image_viewer_page_test.dart`、`shuffle_appbar_actions_test.dart` |
| 媒体密度初始语义与点击持久化重复；本地 URI 与缓存生成 / 命中重复 | 连贯验证前后语义、存储值；文件 URI 合入真实中文文件解析，缓存生成后再次请求检查无重复生成 | `media_grid_density_actions_test.dart`、`local_media_library_test.dart`；键盘与菜单输入、缓存失效和路径穿越仍保留 |
| Sync 改名依赖操作系统一定分配新端口，连续改名只检查最终状态 | 通过传输 port 记录实际发布名称和停止次数，固定端口允许合法端口复用 | `sync_server_controller_test.dart`；真实 HTTP 关闭、旧协议拒绝、未认证保护、启动 / 停止竞态仍使用原边界 |
| Sync 启停幂等、UDP 停止和广播默认选项多次重复准备 | 组合正常生命周期和重复停止；广播周期仍受控；编解码对照独立信封，再 round-trip | `sync_server_controller_test.dart`、`sync_udp_discovery_lifecycle_test.dart`、`sync_udp_announcement_codec_test.dart`、`interface_selector_test.dart` |

安全认证、配对、nonce 重放、协议版本拒绝、敏感设置确认、已发布迁移、媒体路径隔离及异步失败清理均有独立失败机制，未作为重复测试删除。保留原始矩阵和输入规模；没有增加测试排除、跳过或覆盖率过滤。

## 清理过程中发现的现有问题

历史页“滚动后翻页”在测试环境触发 `setState() or markNeedsBuild() called during build`。原来的固定分页栏测试只滚动，翻页测试在顶部操作；合并两者时首次触发这一新组合。

复现步骤：使用 `setUpHistoryScreenWithBulkConversations(tester, count: 25)`；长按选中第 0、1 条；对 `find.byType(ListView).last` 向上拖动 800 像素并 `pump()`；点击“下一页”并 `pump()`。堆栈指向 `lib/core/widgets/pagination/app_paginated_list_shell.dart:81`：`didUpdateWidget` 同步调用 `jumpTo(0)`，滚动通知使 AppBar 在构建中更新。

本轮没有修改这个生产实现，也没有吞掉异常。最终保留原来的独立滚动与翻页场景；“滚动后翻页”组合仍是待修复缺陷，不声称被最终通过的测试保护。失败原始记录保留于 ignored 的 `logs/remaining-cleanup-trial-red.json` / `.log`。

## 测量方法

Windows 原生 PowerShell 7，沿用 `dart_test.yaml` 并发 8。前后使用相同文件集和参数，分别运行三轮范围和三轮全量；以墙钟中位数为主，另报 JSON `done.time` 的 reporter 时间。每次测试由命令层设置 240 秒超时并在超时后杀整棵进程树。所有日志位于 ignored 的 `logs/`，全量当前日志为 `logs/fltest.log`。

```powershell
flutter test --no-pub test/features/favorites test/features/history test/features/media test/features/settings test/features/sync --coverage --coverage-path=logs/remaining-cleanup-<阶段>-scope-<轮次>.lcov --reporter compact --file-reporter=json:logs/remaining-cleanup-<阶段>-scope-<轮次>.json
flutter test --no-pub --coverage --coverage-path=logs/remaining-cleanup-<阶段>-full-<轮次>.lcov --reporter compact --file-reporter=json:logs/remaining-cleanup-<阶段>-full-<轮次>.json
```

范围覆盖率的分母包含加载的其他 feature 和共享基础设施，不代表这五个 feature 本身的覆盖率。JSON loading 包含编译、启动及调度等待；用例时间包含每例 setup 和 widget 初始化。并发下各例耗时总和不能与墙钟直接相加。

前后顺序运行，未交错 A/B；缓存、首次编译和系统负载可能影响结果。不能把全部时间差归因于代码删减，也不能直接外推到 CI 或不带 coverage 的运行。

## 全量结果与关键覆盖

| 指标 | 清理前 | 清理后 |
| --- | ---: | ---: |
| 范围内 Dart 文件 / 自动发现入口 | 118 / 93 | 117 / 93 |
| 范围内测试物理行 | 22,680 | 21,858 |
| 范围运行节点 | 788 | 740 |
| 全量运行节点 | 1,936 | 1,888 |
| 三轮全量墙钟（秒） | 212.647 / 180.147 / 172.736 | 152.813 / 150.615 / 157.083 |
| 全量墙钟中位数（秒） | 180.147 | 152.813 |
| 全量 reporter 中位数（秒） | 174.735 | 148.803 |
| 全量命中行 / 可插桩行 | 22,270 / 24,880 | 22,271 / 24,880 |
| 全量原始行覆盖率 | 89.5096% | 89.5137% |

测试代码净减 822 行，运行节点减少 48 个。全量墙钟中位数减少 27.334 秒（15.2%）；本机这组观测前后区间不重叠，但仍受顺序测量与缓存影响，不保证固定提速比例。

全量逐行比较丢失 0 行、新增 1 行：`output_processing_tab.dart:346`，对应无效正则修正输入时清除旧错误的接线。前后三份全量 LCOV 各自的命中集合完全一致，可插桩分母保持不变。

| 关键 owner（全量） | 清理前覆盖率（命中 / 可插桩） | 清理后覆盖率（命中 / 可插桩） |
| --- | ---: | ---: |
| Favorites | 92.4751%（1,020 / 1,103） | 92.4751%（1,020 / 1,103） |
| History | 91.4508%（353 / 386） | 91.4508%（353 / 386） |
| Media | 91.0230%（2,180 / 2,395） | 91.0230%（2,180 / 2,395） |
| Settings | 88.7149%（4,418 / 4,980） | 88.7349%（4,419 / 4,980） |
| Sync | 75.1850%（1,524 / 2,027） | 75.1850%（1,524 / 2,027） |
| Settings application/transfer | 95.1724%（414 / 435） | 95.1724%（414 / 435） |
| Sync data/security | 88.0734%（96 / 109） | 88.0734%（96 / 109） |
| Core persistence | 94.3152%（365 / 387） | 94.3152%（365 / 387） |

全量 JSON loading 总和的三轮中位数为 423.670 → 387.314 秒；用例执行总和为 400.301 → 329.248 秒；隐藏 fixture 总和为 0.030 → 0.027 秒。加载与用例执行均下降，不能从总和推导每项删减的独立收益。

## 范围复测与下降行归属

| 指标 | 清理前 | 清理后 |
| --- | ---: | ---: |
| 三轮墙钟（秒） | 125.253 / 94.520 / 82.610 | 64.663 / 62.510 / 64.262 |
| 墙钟中位数（秒） | 94.520 | 64.262 |
| reporter 中位数（秒） | 89.428 | 60.603 |
| 命中行 / 可插桩行 | 11,620 / 24,275 | 11,620 / 24,275 |
| 原始行覆盖率 | 47.8682% | 47.8682% |
| loading 总和中位数（秒） | 208.599 | 156.758 |
| 用例执行总和中位数（秒） | 208.554 | 134.670 |
| 隐藏 fixture 总和中位数（秒） | 0.000 | 0.000 |

最终范围墙钟中位数下降 30.258 秒（32.0%）。清理前的三份 LCOV 命中集合一致，清理后的三份也一致。范围新增行与全量相同；唯一丢失行是 `core/widgets/adaptive_master_detail_layout.dart:37` 的紧凑布局选择，由已有 `test/core/widgets/adaptive_master_detail_layout_test.dart` 的 839/840 与 759/760 断点矩阵继续保护，全量仍命中。

| 关键 owner（范围） | 清理前覆盖率（命中 / 可插桩） | 清理后覆盖率（命中 / 可插桩） |
| --- | ---: | ---: |
| Favorites | 91.4778%（1,009 / 1,103） | 91.4778%（1,009 / 1,103） |
| History | 91.4508%（353 / 386） | 91.4508%（353 / 386） |
| Media | 90.9395%（2,178 / 2,395） | 90.9395%（2,178 / 2,395） |
| Settings | 87.9920%（4,382 / 4,980） | 88.0120%（4,383 / 4,980） |
| Sync | 65.4492%（1,326 / 2,026） | 65.4492%（1,326 / 2,026） |
| Settings application/transfer | 90.8046%（395 / 435） | 90.8046%（395 / 435） |
| Sync data/security | 88.0734%（96 / 109） | 88.0734%（96 / 109） |
| Core persistence | 41.3437%（160 / 387） | 41.3437%（160 / 387） |

初次覆盖核对还发现取消新建收藏夹的接线丢失，已恢复为主流程中的实际取消、无新增和重开保存，最终不再丢失。迭代期三轮范围中位数为 62.771 秒；恢复该契约后重新采集三轮，以上表格只使用最终版本。

## 验证与证据

- 最终三轮范围各 740 项、三轮全量各 1,888 项全部通过，完整采集 LCOV 与 JSON reporter。
- `flutter analyze --no-pub`：通过，无 issue。
- `dart run tool/check_import_boundaries.dart`：通过，检查 446 个文件、0 条违规。
- 全部 29 个修改且保留的 Dart 文件执行格式化，提交前再次校验暂存文件格式；`git diff --check` 通过。
- 首次试跑出现四个失败：收藏数量 finder 同时匹配说明与危险删除文案、两条 Sync fake 重复 override、滚动后翻页构建期断言。前两类修正测试，第三类按上文记录并保持原有独立场景；失败试跑未计入最终结果。
- 原始计时、完整日志、逐行差异和 owner 数据位于 `logs/remaining-cleanup-*`；中间试跑单独保留，统计取最终有效三轮。全量当前日志为 `logs/fltest.log`。
- 未做真实设备或外部服务验证；本轮为本地测试维护，报告中的通过结果限于上述实际命令。

# 测试精简第一批结果

## 结论

第一批按“低价值删除 → 重复 Widget / integration 矩阵 → 最慢整页入口”实施，共删除 12 个测试文件、修改 24 个测试文件；总计删除 2,780 行、增加 42 行，净减 2,738 行。生产代码、依赖和数据库 fixture 均未修改。

运行节点从覆盖率口径下的 2,130 个降至 1,970 个，减少 160 个（7.5%）。相同覆盖率命令的墙钟时间从 213.505 秒降至 173.172 秒，减少 40.333 秒（18.9%）。原始行覆盖率下降 0.86 个百分点，仍为 88.80%。

## 前后对比

| 指标 | 删减前 | 删减后 | 变化 |
| --- | ---: | ---: | ---: |
| 测试 Dart 文件 | 259 | 247 | -12（-4.6%） |
| 显式 `test` / `testWidgets` 注册点 | 1,960 | 1,878 | -82（-4.2%） |
| 覆盖率口径运行节点 | 2,130 | 1,970 | -160（-7.5%） |
| 覆盖率口径墙钟时间 | 213.505 秒 | 173.172 秒 | -40.333 秒（-18.9%） |
| 覆盖率口径 reporter 时间 | 3:18 | 2:44 | -0:34（-17.2%） |
| Flutter 原始行覆盖率 | 16,982 / 18,942（89.65%） | 16,812 / 18,933（88.80%） | -0.86 个百分点 |
| 固定删减前 source 集合的行覆盖率 | 16,982 / 18,942（89.65%） | 16,812 / 18,942（88.76%） | -0.90 个百分点 |
| 日常全量运行节点 | 2,131 | 1,970 | -161（-7.6%） |
| 日常全量 reporter 时间 | 1:46 | 1:40 | -0:06（-5.7%） |

覆盖率口径前后均使用：

```powershell
flutter test --exclude-tags=udp --coverage --reporter compact
```

日常口径使用 `flutter test --reporter compact`。删减前日常数据来自审计时已有的 `logs/fltest.log`，只有 reporter 时间；删减后的父进程墙钟为 111.914 秒，但没有等价的删减前父进程墙钟，因此不拿两者计算收益。

Flutter 的 LCOV 只列出被加载的 source。删除 `AppConstrainedContent` 的专用测试后，该文件的 9 行不再进入删减后的原始分母，所以同时给出固定 source 集合的归一化结果。当前 LCOV 不含 function / branch 记录，本报告只比较行覆盖率。

## 本批删减

- 删除恒真或实现镜像测试：根级模板 smoke、布局 token、简单约束包装、noop foreground service、主题内部结构、简单 getter / 默认字段与确定性重复计算。
- 删除脆弱测试：概率性 `List.shuffle` 顺序断言、把短暂 `RenderFlex overflow` 当成功条件的用例、真实 UDP socket smoke、精确 popup 坐标。
- 收敛重复 integration：preset request、collection cascade、Windows back navigation 整文件删除；多协议 generation / notification integration 各保留一个代表协议，完整协议穷举仍由 router 和三个 protocol client 持有。
- 收敛 History / Favorites / Sync 整页矩阵：删除 controller 已覆盖的 latest-wins、stale result、分页、rename / delete refresh，以及重复 viewport / platform smoke。
- 收敛 ChatScreen：模板语言保留“切分支并发送、损坏模板 inline 诊断、跨会话隔离、同 ID 模板刷新”四条 UI 脊柱；workspace ownership 保留“A→B→A 草稿、取消编辑、卸载重挂、带模板编辑”四条 UI 脊柱；普通标题、字数、固定序列和 checkpoint 的规则回归各自低层 owner。
- 收敛 SettingsScreen：provider / model 与每类 prompt 只保留创建持久化主流程；排序、变量 reconcile、敏感传输等独有行为继续保留，重复 edit / delete Widget CRUD 交给 controller / repository。
- 将 endpoint resolver 的逐行测试节点合并为保留 `reason` 的表驱动测试，输入矩阵与代码覆盖不变。

## Surviving owners

| 被删的上层重复 | 保留的契约 owner |
| --- | --- |
| History latest-wins、stale、rename / delete refresh Widget 用例 | `history_pagination_controller_test.dart` 与 repository 测试 |
| 模板条件、数字比较、select 编解码的 ChatScreen 穷举 | template compiler / evaluator、composer command 与 message builder 测试 |
| 草稿跨会话、模板变量隔离的多种页面排列 | `composer_draft_controller_test.dart` 加四条代表 UI 脊柱 |
| Settings 实体 edit / delete 整页 CRUD | 各 controller、SQLite repository 和一条 create / persist Widget 主流程 |
| 三协议 integration 笛卡尔积 | protocol router 的全协议委派与三个协议 client / parser 测试 |
| collection / preset 的跨层重复 integration | repository 事务、application builder 与现存用户流测试 |
| 布局 token、约束包装、主题字段镜像 | 使用这些组件的极端 viewport / 可达性 Widget 测试 |

绝对保留项未改动：SQLite 已发布迁移、Sync v4 typed protocol 与加密 / replay 防护、HTTP 信任域和脱敏、三协议 parser、SSE 边界、消息树、reasoning / content 分离、generation lifecycle / race / durable save。

## 覆盖率取舍

命中行减少 170 行，主要来自本批主动放弃的上层重复：数字变量输入控件 28 行、SettingsScreen 及其 CRUD 列表 / 表单约 88 行、`Favorite` 简单模型 13 行、约束包装 9 行、noop foreground service 5 行，其余为页面分支的零散接线行。

这一结果符合本批目标：允许简单展示、getter 与 framework wiring 的覆盖下降，换取整页测试和重复 integration 的减少；没有通过新增 mock 或等价测试把覆盖率数字补回去。

## 验证

- `flutter test test/features/chat/presentation/chat_screen_test.dart --reporter compact`：55 个测试通过，墙钟 44.753 秒。
- `flutter test test/features/settings/presentation/settings_screen_test.dart --reporter compact`：29 个测试通过，墙钟 23.165 秒。
- `flutter test --reporter compact`：1,970 个测试通过，reporter 1:40，父进程墙钟 111.914 秒。
- `flutter test --exclude-tags=udp --coverage --reporter compact`：1,970 个测试通过，reporter 2:44，父进程墙钟 173.172 秒。
- `flutter analyze`：通过，无 issue。
- `dart run tool/check_import_boundaries.dart`：通过，检查 392 个文件，0 条违规。

## 后续

本批净删 2,738 行，约为审计候选 9,963 行的 27.5%。覆盖率模式已接近方案的 20% 阶段目标，日常并行全量只下降 5.7%，说明剩余成本仍集中在慢分片和 Flutter 编译固定开销。

下一批应独立处理 Chat generation / protocol 分层和媒体视频交互矩阵；不要继续删除毫秒级迁移、安全或 parser 纯函数测试来凑用例数。
